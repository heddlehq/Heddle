defmodule HeddleUI.FlowLive.ValidateRulesTest do
  use ExUnit.Case, async: true

  alias HeddleUI.FlowLive.ValidateRules

  defp rule(attrs) do
    Map.merge(
      %{
        "key" => "name",
        "type" => "string",
        "required" => true,
        "min" => "",
        "max" => "",
        "pattern" => "",
        "options" => "",
        "message" => %{"en" => "", "pt_BR" => ""}
      },
      attrs
    )
  end

  test "writes a schema Heddle.Schema reads, with the fields in order, and reads it back" do
    rules = [
      rule(%{"key" => "zeta", "min" => "3", "message" => %{"en" => "", "pt_BR" => "Curto"}}),
      rule(%{"key" => "age", "type" => "integer", "required" => false, "min" => "18"}),
      rule(%{"key" => "plan", "type" => "enum", "options" => "Free\n Pro \n"}),
      rule(%{"key" => "since", "type" => "date", "max" => "2026-12-31"}),
      rule(%{"key" => "code", "pattern" => "^\\d{3}$"})
    ]

    json = ValidateRules.to_schema(rules)

    assert {:ok, schema} = Heddle.Schema.parse(json)
    assert {:ok, read} = ValidateRules.from_schema(json)
    assert Enum.map(read, & &1["key"]) == ["zeta", "age", "plan", "since", "code"]
    assert Enum.at(read, 0)["message"] == %{"en" => "", "pt_BR" => "Curto"}
    assert Enum.at(read, 1)["required"] == false
    assert Enum.at(read, 2)["options"] == "Free\nPro"

    assert {:error, issues} =
             Heddle.Schema.validate(schema, %{
               "zeta" => "ab",
               "age" => "12",
               "plan" => "Gold",
               "since" => "2027-01-01",
               "code" => "12"
             })

    assert Enum.map(issues, & &1["path"]) == ~w(age code plan since zeta)

    valid = %{
      "age" => "30",
      "zeta" => "abc",
      "plan" => "Pro",
      "since" => "2026-01-01",
      "code" => "123"
    }

    assert {:ok, %{"age" => 30}} = Heddle.Schema.validate(schema, valid)
  end

  test "leaves out a bound that isn't a number, and keeps a field still being named" do
    json = ValidateRules.to_schema([rule(%{"key" => " "}), rule(%{"min" => "abc"})])

    assert Jason.decode!(json) == %{
             "" => %{"type" => "string", "trim" => true},
             "name" => %{"type" => "string", "trim" => true}
           }

    assert {:error, "every field needs a name"} = Heddle.Schema.parse(json)
  end

  test "reads the short form, and says when only JSON can say it" do
    assert {:ok, [%{"key" => "email", "type" => "email", "required" => false}]} =
             ValidateRules.from_schema(~s({"email": "email?"}))

    assert {:ok, []} = ValidateRules.from_schema("")

    for complex <- [
          ~s({"address": {"city": "string"}}),
          ~s({"tags": ["string"]}),
          ~s({"type": "object", "fields": {}}),
          ~s({"name": {"type": "string", "lowercase": true}}),
          ~s({"name": {"type": "string", "message": "One for all"}}),
          "{"
        ] do
      assert ValidateRules.from_schema(complex) == :complex, complex
    end
  end

  test "makes the rules of a form's fields" do
    fields = [
      %{"key" => "email", "type" => "email", "required" => true},
      %{"key" => "plan", "type" => "select", "options" => ["Free", "Pro"], "required" => false},
      %{"key" => "bio", "type" => "textarea", "required" => false}
    ]

    assert [
             %{"key" => "email", "type" => "email", "required" => true},
             %{"key" => "plan", "type" => "enum", "options" => "Free\nPro"},
             %{"key" => "bio", "type" => "string", "required" => false}
           ] = ValidateRules.from_form(fields)
  end
end
