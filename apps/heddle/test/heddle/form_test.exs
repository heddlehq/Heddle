defmodule Heddle.FormTest do
  use ExUnit.Case, async: true

  alias Heddle.Form

  describe "parse/1" do
    test "reads JSON text and fills in every key" do
      assert {:ok, [field]} =
               Form.parse(~s([{"key": "email", "label": " Email ", "type": "email"}]))

      assert field == %{
               "key" => "email",
               "label" => "Email",
               "type" => "email",
               "required" => false,
               "placeholder" => "",
               "options" => []
             }
    end

    test "takes options as a list or one per line, and an unknown type as text" do
      assert {:ok, [field]} =
               Form.parse([%{"key" => "plan", "type" => "nope", "options" => "A\n\nB\nA"}])

      assert field["type"] == "text"
      assert field["options"] == ["A", "B"]
    end

    test "has nothing for an empty control, and an error for what isn't a list" do
      assert Form.parse("") == {:ok, []}
      assert {:error, _message} = Form.parse("{")
      assert {:error, _message} = Form.parse(~s({"key": "a"}))
      assert {:error, _message} = Form.parse([1])
    end

    test "the default fields are valid" do
      assert {:ok, fields} = Form.parse(Form.default_json())
      assert Form.validate(fields) == :ok
    end
  end

  describe "validate/1" do
    test "asks for fields, valid unique keys, labels and options" do
      field = %{"key" => "a", "label" => "A", "type" => "text", "options" => []}

      assert {:error, "has no fields"} = Form.validate([])

      assert {:error, "has a field with an invalid key" <> _} =
               Form.validate([%{field | "key" => "1a"}])

      assert {:error, "has two fields with the same key"} = Form.validate([field, field])

      assert {:error, "has a field without label" <> _} =
               Form.validate([%{field | "label" => ""}])

      assert {:error, "has a select without options" <> _} =
               Form.validate([%{field | "type" => "select"}])

      assert Form.validate([field]) == :ok
    end
  end

  describe "cast/2" do
    setup do
      {:ok, fields} =
        Form.parse([
          %{"key" => "name", "label" => "Name", "type" => "text", "required" => true},
          %{"key" => "email", "label" => "Email", "type" => "email"},
          %{"key" => "age", "label" => "Age", "type" => "number"},
          %{"key" => "day", "label" => "Day", "type" => "date"},
          %{"key" => "plan", "label" => "Plan", "type" => "select", "options" => ["Free", "Pro"]},
          %{"key" => "terms", "label" => "Terms", "type" => "checkbox", "required" => true},
          %{"key" => "news", "label" => "News", "type" => "checkbox"}
        ])

      %{fields: fields}
    end

    test "converts each value by its type and ignores other params", %{fields: fields} do
      params = %{
        "name" => " Ana ",
        "email" => "ana@example.com",
        "age" => "3,5",
        "day" => "2026-11-08",
        "plan" => "Pro",
        "terms" => "true",
        "extra" => "ignored"
      }

      assert {:ok, values} = Form.cast(fields, params)

      assert values == %{
               "name" => "Ana",
               "email" => "ana@example.com",
               "age" => 3.5,
               "day" => "2026-11-08",
               "plan" => "Pro",
               "terms" => true,
               "news" => false
             }
    end

    test "says what is wrong with each field, and keeps what was sent", %{fields: fields} do
      params = %{
        "name" => "",
        "email" => "nope",
        "age" => "x",
        "day" => "08/11",
        "plan" => "Gold"
      }

      assert {:error, errors, values} = Form.cast(fields, params)

      assert errors == %{
               "name" => :required,
               "email" => :invalid_email,
               "age" => :invalid_number,
               "day" => :invalid_date,
               "plan" => :invalid_option,
               "terms" => :required
             }

      assert values["email"] == "nope"
    end

    test "an empty optional field is nil, and a long text is refused", %{fields: fields} do
      long = String.duplicate("a", Form.max_length() + 1)

      assert {:error, %{"name" => :too_long}, _values} =
               Form.cast(fields, %{"name" => long, "terms" => "on"})

      assert {:ok, %{"email" => nil, "age" => nil}} =
               Form.cast(fields, %{"name" => "Ana", "terms" => "on", "age" => [1]})
    end
  end

  test "key_from_label/1 makes a key from any label" do
    assert Form.key_from_label("Nome completo") == "nome_completo"
    assert Form.key_from_label("Endereço de e-mail") == "endereco_de_e_mail"
    assert Form.key_from_label("2º telefone") == "field_2_telefone"
    assert Form.key_from_label("!!!") == "field"
  end

  test "encode/1 keeps only what a field needs" do
    {:ok, fields} = Form.parse([%{"key" => "a", "label" => "A"}])

    assert Form.encode(fields) ==
             ~s([{"key":"a","label":"A","required":false,"type":"text"}])
  end
end
