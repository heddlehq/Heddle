defmodule HeddleUI.FlowLive.FormTriggerEditorTest do
  use HeddleUI.ConnCase, async: true

  import Phoenix.LiveViewTest
  import HeddleCore.AccountsFixtures
  import HeddleCore.FlowsFixtures

  @fields ~s([{"key":"name","label":"Name","type":"text","required":true}])

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
          }
        ]
      )

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/flows/#{flow.id}")

    render_hook(lv, "open_node_config", %{
      "nodeId" => "form",
      "nodeData" => %{
        "id" => "form",
        "type" => "Form Trigger",
        "label" => "Form",
        "controls" => %{
          "title" => %{"value" => "Join", "type" => "text", "label" => "Title"},
          "fields" => %{"value" => @fields, "type" => "form_fields", "label" => "Fields"}
        }
      }
    })

    %{lv: lv, flow: flow, scope: user_scope_fixture(user)}
  end

  test "the drawer shows the link of the form and its fields", %{lv: lv} do
    assert has_element?(lv, "#form-link-url")
    assert lv |> element("#form-link-url") |> render() =~ "/f/"
    assert has_element?(lv, "#form-link-open")
    assert has_element?(lv, "#form-link-test")
    assert has_element?(lv, ~s(#form-field-label-0[value="Name"]))
  end

  test "editing a card sends the fields as JSON, and a key follows its label", %{lv: lv} do
    lv
    |> element("#node-config-form")
    |> render_change(%{
      "fields" => %{
        "0" => %{"label" => "Full name", "key" => "name", "type" => "text", "required" => "true"}
      }
    })

    assert_push_event(lv, "update_node_data", %{nodeId: "form", data: %{"fields" => json}})
    assert [%{"key" => "full_name", "label" => "Full name"}] = Jason.decode!(json)

    lv |> element("#form-field-add") |> render_click()
    assert_push_event(lv, "update_node_data", %{data: %{"fields" => json}})
    assert [_name, %{"key" => "field_2", "label" => ""}] = Jason.decode!(json)

    lv
    |> element("#node-config-form")
    |> render_change(%{
      "fields" => %{
        "0" => %{"label" => "Full name", "key" => "who", "type" => "text"},
        "1" => %{"label" => "E-mail address", "key" => "field_2", "type" => "email"}
      }
    })

    # A key written by hand stays, and a new field's follows its label.
    assert_push_event(lv, "update_node_data", %{data: %{"fields" => json}})
    assert [%{"key" => "who"}, %{"key" => "e_mail_address"}] = Jason.decode!(json)

    lv |> element("#form-field-remove-1") |> render_click()
    assert_push_event(lv, "update_node_data", %{data: %{"fields" => json}})
    assert [%{"key" => "who"}] = Jason.decode!(json)
  end

  test "a new field takes its key from its label", %{lv: lv} do
    lv |> element("#form-field-add") |> render_click()
    assert_push_event(lv, "update_node_data", %{data: %{"fields" => _json}})

    lv
    |> element("#node-config-form")
    |> render_change(%{
      "fields" => %{
        "0" => %{"label" => "Name", "key" => "name", "type" => "text"},
        "1" => %{"label" => "Endereço", "key" => "", "type" => "text"}
      }
    })

    assert_push_event(lv, "update_node_data", %{data: %{"fields" => json}})
    assert [_name, %{"key" => "endereco"}] = Jason.decode!(json)
  end

  test "makes a Spool table from the fields", %{lv: lv, scope: scope} do
    lv |> element("#form-link-table") |> render_click()

    assert [%{name: "Join", columns: [%{"name" => "name", "type" => "text"}]}] =
             HeddleCore.Spool.list_tables(scope)
  end

  test "a new link replaces the old one", %{lv: lv} do
    old = lv |> element("#form-link-url") |> render()
    lv |> element("#form-link-regenerate") |> render_click()
    refute lv |> element("#form-link-url") |> render() == old
  end
end
