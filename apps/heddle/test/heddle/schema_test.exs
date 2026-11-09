defmodule Heddle.SchemaTest do
  use ExUnit.Case, async: true

  alias Heddle.Schema

  defp run(schema, value) do
    {:ok, schema} = Schema.parse(schema)
    Schema.validate(schema, value)
  end

  defp issues(schema, value) do
    {:error, issues} = run(schema, value)
    Enum.map(issues, &{&1["path"], &1["code"], &1["message"]})
  end

  describe "parse/1" do
    test "reads JSON text, or the value it decodes to" do
      assert {:ok, _schema} = Schema.parse(~s({"name": "string"}))
      assert {:ok, _schema} = Schema.parse(%{"name" => "string"})
      assert {:ok, _schema} = Schema.parse(["email"])
    end

    test "says what is wrong with a schema, and where" do
      assert Schema.parse("") == {:error, "the schema is empty"}
      assert Schema.parse("{") == {:error, "the schema isn't valid JSON"}

      assert {:error, "user.age: \"int\" isn't a type. Use one of: " <> _types} =
               Schema.parse(%{"user" => %{"age" => "int"}})

      assert Schema.parse(%{"name" => %{"type" => "string", "minimum" => 2}}) ==
               {:error, "name: \"minimum\" isn't an option of a string"}

      assert Schema.parse(%{"type" => "enum", "values" => []}) ==
               {:error, "an enum needs values, a list of what it may be"}

      assert Schema.parse(%{"code" => %{"type" => "string", "pattern" => "("}}) ==
               {:error, "code: pattern isn't a valid regular expression"}

      assert Schema.parse(%{"tags" => ["string", "number"]}) ==
               {:error, "tags: a list in a schema holds one schema, the one of its items"}

      assert Schema.parse(%{"n" => %{"type" => "integer", "min" => "1"}}) ==
               {:error, "n: min is a number"}
    end
  end

  describe "objects" do
    @user ~s({"name": {"type": "string", "min": 2, "trim": true}, "email": "email", "age": "integer?"})

    test "takes what matches, and leaves out keys it doesn't know" do
      assert run(@user, %{"name" => " Ana ", "email" => "ana@example.com", "admin" => true}) ==
               {:ok, %{"name" => "Ana", "email" => "ana@example.com"}}
    end

    test "reports every field that fails, with its path" do
      assert issues(@user, %{"name" => "A", "age" => "ten"}) == [
               {"age", "invalid_type", "Expected an integer, got text"},
               {"email", "required", "Required"},
               {"name", "too_small", "Must have at least 2 characters"}
             ]
    end

    test "keeps or refuses unknown keys when asked" do
      keep = %{"type" => "object", "fields" => %{"a" => "string"}, "unknown" => "keep"}
      strict = %{keep | "unknown" => "error"}

      assert run(keep, %{"a" => "x", "b" => 1}) == {:ok, %{"a" => "x", "b" => 1}}

      assert issues(strict, %{"a" => "x", "b" => 1}) == [
               {"b", "unknown_key", "Isn't allowed here"}
             ]
    end

    test "nests, with paths into lists" do
      schema = %{"items" => [%{"sku" => "string", "qty" => %{"type" => "integer", "min" => 1}}]}

      assert issues(schema, %{"items" => [%{"sku" => "a", "qty" => 1}, %{"qty" => 0}]}) == [
               {"items[1].qty", "too_small", "Must be at least 1"},
               {"items[1].sku", "required", "Required"}
             ]
    end

    test "fills in defaults, and a null is only fine when nullable" do
      schema = %{
        "plan" => %{"type" => "enum", "values" => ["free", "pro"], "default" => "free"},
        "note" => %{"type" => "string", "nullable" => true}
      }

      assert run(schema, %{"note" => nil}) == {:ok, %{"plan" => "free", "note" => nil}}

      assert issues(schema, %{"plan" => nil, "note" => nil}) == [
               {"plan", "invalid_enum", "Must be one of: \"free\", \"pro\""}
             ]
    end

    test "a plain object takes any keys" do
      assert run(%{"meta" => "object"}, %{"meta" => %{"a" => 1}}) ==
               {:ok, %{"meta" => %{"a" => 1}}}
    end
  end

  describe "strings" do
    test "checks formats" do
      assert issues("email", "nope") == [{"", "invalid_format", "Must be an email address"}]

      assert issues("url", "example.com") == [
               {"", "invalid_format", "Must be a URL, like https://example.com"}
             ]

      assert {:ok, _} = run("url", "https://example.com/a?b=1")
      assert {:ok, _} = run("uuid", "123e4567-e89b-12d3-a456-426614174000")
      assert issues("uuid", "123") == [{"", "invalid_format", "Must be a UUID"}]
    end

    test "checks length, pattern and what it starts or ends with" do
      code = %{"type" => "string", "pattern" => "^[A-Z]{3}-\\d+$"}
      assert {:ok, "ABC-12"} = run(code, "ABC-12")
      assert issues(code, "abc") == [{"", "invalid_format", "Must match ^[A-Z]{3}-\\d+$"}]

      assert issues(%{"type" => "string", "length" => 2}, "abc") ==
               [{"", "too_big", "Must have exactly 2 characters"}]

      assert issues(%{"type" => "string", "max" => 1}, "ab") ==
               [{"", "too_big", "Must have at most 1 character"}]

      assert issues(%{"type" => "string", "starts_with" => "+55"}, "11 9999") ==
               [{"", "invalid_format", "Must start with \"+55\""}]
    end

    test "changes text before checking it" do
      assert run(%{"type" => "email", "trim" => true, "lowercase" => true}, " Ana@Example.COM ") ==
               {:ok, "ana@example.com"}
    end

    test "only turns numbers into text when asked" do
      assert issues("string", 42) == [{"", "invalid_type", "Expected a string, got an integer"}]
      assert run(%{"type" => "string", "coerce" => true}, 42) == {:ok, "42"}
    end

    test "a message replaces the errors of its value" do
      schema = %{
        "cpf" => %{
          "type" => "string",
          "length" => 11,
          "message" => "Enter the 11 digits of the CPF"
        }
      }

      assert issues(schema, %{"cpf" => "123"}) == [
               {"cpf", "too_small", "Enter the 11 digits of the CPF"}
             ]
    end
  end

  describe "numbers" do
    test "checks bounds" do
      price = %{"type" => "number", "gt" => 0, "max" => 100}
      assert {:ok, 9.9} = run(price, 9.9)
      assert issues(price, 0) == [{"", "too_small", "Must be more than 0"}]
      assert issues(price, 101) == [{"", "too_big", "Must be at most 100"}]

      assert issues(%{"type" => "number", "multiple_of" => 0.5}, 1.2) ==
               [{"", "not_multiple", "Must be a multiple of 0.5"}]
    end

    test "an integer is a whole number, and 3.0 counts" do
      assert run("integer", 3.0) == {:ok, 3}
      assert issues("integer", 3.5) == [{"", "invalid_type", "Expected an integer, got a number"}]
    end

    test "reads numbers from text when asked" do
      assert issues("number", "42") == [{"", "invalid_type", "Expected a number, got text"}]
      assert run(%{"type" => "integer", "coerce" => true}, " 42 ") == {:ok, 42}
      assert run(%{"type" => "number", "coerce" => true}, "4.5") == {:ok, 4.5}

      assert issues(%{"type" => "number", "coerce" => true}, "4,5") ==
               [{"", "invalid_type", "Expected a number, got text"}]
    end
  end

  describe "other types" do
    test "booleans, read from text when asked" do
      assert run("boolean", false) == {:ok, false}
      assert issues("boolean", "yes") == [{"", "invalid_type", "Expected a boolean, got text"}]
      assert run(%{"type" => "boolean", "coerce" => true}, "Yes") == {:ok, true}
      assert run(%{"type" => "boolean", "coerce" => true}, 0) == {:ok, false}
    end

    test "dates, with bounds" do
      schema = %{"type" => "date", "min" => "2026-01-01"}
      assert run(schema, "2026-03-01") == {:ok, "2026-03-01"}
      assert run(schema, "2026-03-01T10:00:00Z") == {:ok, "2026-03-01T10:00:00Z"}
      assert issues(schema, "2025-12-31") == [{"", "too_small", "Must be on or after 2026-01-01"}]

      assert issues("date", "31/12/2026") ==
               [{"", "invalid_format", "Must be a date, like 2026-12-24 or 2026-12-24T18:00:00Z"}]
    end

    test "arrays, with sizes and unique items" do
      tags = %{"type" => "array", "items" => "string", "min" => 1, "unique" => true}
      assert run(tags, ["a", "b"]) == {:ok, ["a", "b"]}
      assert issues(tags, []) == [{"", "too_small", "Must have at least 1 item"}]
      assert issues(tags, ["a", "a"]) == [{"", "not_unique", "Must not repeat items"}]

      assert issues(tags, ["a", 1]) == [
               {"[1]", "invalid_type", "Expected a string, got an integer"}
             ]
    end

    test "literals, unions and any" do
      assert issues(%{"type" => "literal", "value" => true}, false) ==
               [{"", "invalid_literal", "Must be true"}]

      id = %{"type" => "union", "of" => ["integer", "uuid"]}
      assert run(id, 7) == {:ok, 7}
      assert issues(id, "x") == [{"", "invalid_union", "Doesn't match any of the allowed shapes"}]

      assert run(%{"data" => "any"}, %{}) == {:ok, %{}}
      assert run("any", nil) == {:ok, nil}
    end

    test "a missing value is only fine when optional" do
      assert issues("string", nil) == [{"", "invalid_type", "Expected a string, got null"}]
      assert run("string?", nil) |> elem(0) == :error
      assert run(%{"a" => "string?"}, %{}) == {:ok, %{}}
    end
  end
end
