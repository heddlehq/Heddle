defmodule HeddleUI.FlowLive.SubflowEditorTest do
  use HeddleUI.ConnCase, async: true

  import Phoenix.LiveViewTest
  import HeddleCore.AccountsFixtures
  import HeddleCore.FlowsFixtures

  setup %{conn: conn} do
    user = user_fixture()
    workspace = workspace_fixture(user)
    target = flow_fixture(user: user, workspace: workspace, name: "Score lead")
    _elsewhere = flow_fixture(name: "Someone else's")

    flow =
      flow_fixture(
        user: user,
        workspace: workspace,
        name: "New leads",
        nodes: [
          %{
            "id" => "call",
            "type" => "Subflow",
            "label" => "Call",
            "controls" => %{"subflow_id" => to_string(target.id)}
          }
        ]
      )

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/flows/#{flow.id}")

    %{lv: lv, target: target}
  end

  defp open(lv, value) do
    render_hook(lv, "open_node_config", %{
      "nodeId" => "call",
      "nodeData" => %{
        "id" => "call",
        "type" => "Subflow",
        "label" => "Call",
        "controls" => %{
          "subflow_id" => %{"value" => value, "type" => "flow", "label" => "Flow"}
        }
      }
    })
  end

  test "picks among the other flows of the workspace", %{lv: lv, target: target} do
    open(lv, "")

    assert has_element?(lv, "#node-flow-subflow_id option[value='#{target.id}']", "Score lead")
    refute has_element?(lv, "#node-flow-subflow_id option", "New leads")
    refute has_element?(lv, "#node-flow-subflow_id option", "Someone else's")
    refute has_element?(lv, "#node-flow-open-subflow_id")
  end

  test "links to the flow picked", %{lv: lv, target: target} do
    open(lv, to_string(target.id))

    assert has_element?(lv, "#node-flow-subflow_id option[value='#{target.id}'][selected]")
    assert has_element?(lv, "#node-flow-open-subflow_id[href='/flows/#{target.id}']")
  end
end
