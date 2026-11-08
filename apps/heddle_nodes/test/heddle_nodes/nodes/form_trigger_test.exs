defmodule HeddleNodes.Nodes.FormTriggerTest do
  use ExUnit.Case, async: true

  alias HeddleNodes.Nodes.FormTrigger

  test "passes on what was sent as its result" do
    context = %{"form" => %{"email" => "ana@example.com"}}

    assert {:ok, %{"result" => %{"email" => "ana@example.com"}}, :exec} =
             FormTrigger.handler(context, nil)
  end

  test "is a trigger whose default fields are valid" do
    definition = FormTrigger.definition()
    assert definition.category == :trigger
    assert definition.inputs == []

    fields = Enum.find(definition.ui_fields, &(&1.name == :fields))
    assert fields.type == :form_fields
    assert {:ok, parsed} = Heddle.Form.parse(fields.default)
    assert Heddle.Form.validate(parsed) == :ok
  end

  test "a run from the form starts at the node and sees what was sent" do
    flow = %{
      id: 1,
      workspace_id: 1,
      nodes: [
        %{"id" => "f", "type" => "Form Trigger", "label" => "Form", "controls" => %{}},
        %{"id" => "s", "type" => "Start", "label" => "Start", "controls" => %{}},
        %{
          "id" => "v",
          "type" => "Variable",
          "label" => "Name",
          "controls" => %{
            "var_name" => "who",
            "var_value" => "{{form.name}}",
            "var_type" => "string"
          }
        }
      ],
      connections: [%{"source" => "f", "sourceOutput" => "exec", "target" => "v"}]
    }

    input = %{"trigger" => "form", "node_id" => "f", "form" => %{"name" => "Ana"}}

    assert {:ok, context} = HeddleNodes.Runner.run(flow, input)
    assert context["result"] == %{"name" => "Ana"}
    assert context["form"] == %{"name" => "Ana"}
    assert %{"who" => _value} = context["variables"]
  end
end
