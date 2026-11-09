defmodule HeddleNodes.Nodes.ValidateTest do
  use ExUnit.Case, async: true

  alias HeddleNodes.Nodes.Validate

  @schema ~s({"email": {"type": "email", "trim": true}, "age": {"type": "integer", "coerce": true, "min": 18}})

  defp context(data, schema \\ @schema),
    do: Map.merge(data, %{"validation_data" => "{{body}}", "validation_schema" => schema})

  test "goes on through valid with the data as the schema leaves it" do
    context = context(%{"body" => %{"email" => " ana@example.com ", "age" => "30", "x" => 1}})

    assert {:ok, %{"result" => result}, "valid"} = Validate.handler(context, nil)
    assert result == %{"email" => "ana@example.com", "age" => 30}
  end

  test "goes on through invalid with the errors and the data as it came" do
    body = %{"email" => "nope", "age" => "12"}

    assert {:ok, %{"result" => result}, "invalid"} =
             Validate.handler(context(%{"body" => body}), nil)

    assert result["data"] == body
    assert result["message"] == "age: Must be at least 18; email: Must be an email address"

    assert [
             %{"path" => "age", "code" => "too_small"},
             %{"path" => "email", "code" => "invalid_format"}
           ] =
             result["errors"]
  end

  test "reads Data written as JSON with placeholders" do
    context =
      %{"form" => %{"mail" => "ana@example.com"}}
      |> Map.merge(%{
        "validation_data" => ~s({"email": "{{form.mail}}", "age": 40}),
        "validation_schema" => @schema
      })

    assert {:ok, _context, "valid"} = Validate.handler(context, nil)
  end

  test "takes JSON that a previous node handed over as text" do
    context = context(%{"body" => ~s({"email": "ana@example.com", "age": 20})})
    assert {:ok, _context, "valid"} = Validate.handler(context, nil)
  end

  test "a bare type name is a schema" do
    context = %{
      "result" => "ana@example.com",
      "validation_data" => "{{result}}",
      "validation_schema" => "email"
    }

    assert {:ok, %{"result" => "ana@example.com"}, "valid"} = Validate.handler(context, nil)
  end

  test "in a run a form started, the first Validate answers the form" do
    context = Map.put(context(%{"body" => %{"email" => "nope", "age" => 30}}), "trigger", "form")

    assert {:respond, %{"form" => "invalid", "errors" => [%{"path" => "email"}]}, answered,
            "invalid"} = Validate.handler(context, nil)

    assert answered["_form_answered"]

    # A later one has nothing left to answer.
    assert {:ok, _context, "invalid"} = Validate.handler(answered, nil)

    valid = Map.put(context(%{"body" => %{"email" => "a@b.co", "age" => 30}}), "trigger", "form")
    assert {:respond, %{"form" => "valid"}, _context, "valid"} = Validate.handler(valid, nil)
  end

  test "fails when the schema can't be read" do
    assert {:error, "Schema: email: \"mail\" isn't a type. Use one of: " <> _} =
             Validate.handler(context(%{"body" => %{}}, ~s({"email": "mail"})), nil)
  end

  test "the default schema is a valid one" do
    default = Validate.definition().ui_fields |> Enum.find(&(&1.name == :validation_schema))
    assert {:ok, _schema} = Heddle.Schema.parse(default.default)
  end
end
