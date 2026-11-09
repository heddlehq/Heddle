defmodule HeddleUI.FlowLive.ValidateEditorTest do
  use HeddleUI.ConnCase, async: true

  import Phoenix.LiveViewTest
  import HeddleCore.AccountsFixtures
  import HeddleCore.FlowsFixtures

  @fields ~s([{"key":"name","label":"Name","type":"text","required":true},{"key":"plan","label":"Plan","type":"select","options":["Free","Pro"],"required":false}])
  @schema ~s({"name": {"type": "string", "min": 3, "message": {"pt_BR": "Nome curto"}}, "email": "email?"})

  setup %{conn: conn} do
    user = user_fixture()
    workspace = workspace_fixture(user)

    flow =
      flow_fixture(
        user: user,
        workspace: workspace,
        nodes: [
          %{
            "id" => "form",
            "type" => "Form Trigger",
            "label" => "Form",
            "controls" => %{"title" => "Join", "fields" => @fields}
          },
          %{
            "id" => "check",
            "type" => "Validate",
            "label" => "Check",
            "controls" => %{"validation_data" => "{{result}}", "validation_schema" => @schema}
          }
        ]
      )

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/flows/#{flow.id}")
    %{lv: lv}
  end

  defp open(lv, schema \\ @schema) do
    render_hook(lv, "open_node_config", %{
      "nodeId" => "check",
      "nodeData" => %{
        "id" => "check",
        "type" => "Validate",
        "label" => "Check",
        "controls" => %{
          "validation_data" => %{"value" => "{{result}}", "type" => "textarea", "label" => "Data"},
          "validation_schema" => %{"value" => schema, "type" => "schema", "label" => "Rules"}
        }
      }
    })
  end

  test "shows a card per field, with its rules and its message in each language", %{lv: lv} do
    open(lv)

    assert has_element?(lv, "#validate-rule-key-0[value='name']")
    assert has_element?(lv, "#validate-rule-min-0[value='3']")
    assert has_element?(lv, "#validate-rule-message-0-pt_BR[value='Nome curto']")
    assert has_element?(lv, "#validate-rule-message-0-en[value='']")
    assert has_element?(lv, "#validate-rule-key-1[value='email']")
    refute has_element?(lv, "#validate-rule-required-1[checked]")
    refute has_element?(lv, "#node-field-validation_schema")
  end

  test "a change in a card becomes the schema, which reaches the canvas", %{lv: lv} do
    open(lv)

    lv
    |> form("#node-config-form")
    |> render_change(%{
      "validation_schema" => %{
        "0" => %{
          "key" => "name",
          "type" => "string",
          "required" => "true",
          "min" => "4",
          "message" => %{"en" => "Too short", "pt_BR" => "Nome curto"}
        }
      }
    })

    assert_push_event(lv, "update_node_data", %{data: %{"validation_schema" => schema}})

    assert Jason.decode!(schema) == %{
             "name" => %{
               "type" => "string",
               "min" => 4,
               "trim" => true,
               "message" => %{"en" => "Too short", "pt_BR" => "Nome curto"}
             },
             "email" => %{"type" => "email", "optional" => true, "trim" => true}
           }
  end

  test "starts from the fields of the form, and checks what it sends", %{lv: lv} do
    open(lv)

    lv |> element("#validate-use-form") |> render_click()

    assert_push_event(lv, "update_node_data", %{data: %{"validation_schema" => schema}})
    assert_push_event(lv, "update_node_data", %{data: %{"validation_data" => "{{form}}"}})

    assert %{"name" => %{"type" => "string"}, "plan" => %{"values" => ["Free", "Pro"]}} =
             Jason.decode!(schema)

    assert has_element?(lv, "#validate-rule-key-1[value='plan']")
  end

  test "adds and removes fields", %{lv: lv} do
    open(lv)

    lv |> element("#validate-rule-add") |> render_click()
    assert has_element?(lv, "#validate-rule-key-2[value='field_3']")

    lv |> element("#validate-rule-remove-0") |> render_click()
    assert has_element?(lv, "#validate-rule-key-0[value='email']")
    refute has_element?(lv, "#validate-rule-key-2")
  end

  test "edits as JSON when asked, and what only JSON says", %{lv: lv} do
    open(lv)
    lv |> element("#validate-json-toggle") |> render_click()
    assert has_element?(lv, "#node-field-validation_schema")
    lv |> element("#validate-json-toggle") |> render_click()
    assert has_element?(lv, "#validate-rule-key-0")

    open(lv, ~s({"address": {"city": "string"}}))
    assert has_element?(lv, "#node-field-validation_schema")
    assert has_element?(lv, "#validate-json-only")
    refute has_element?(lv, "#validate-json-toggle")
  end
end
