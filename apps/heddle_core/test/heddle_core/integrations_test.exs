defmodule HeddleCore.IntegrationsTest do
  use HeddleCore.DataCase, async: true

  import HeddleCore.AccountsFixtures
  import HeddleCore.FlowsFixtures

  alias HeddleCore.Integrations

  setup do
    user = user_fixture()
    workspace = workspace_fixture(user)
    %{user: user, workspace: workspace, scope: user_scope_fixture(user)}
  end

  defp slack_node,
    do: %{
      "id" => "1",
      "type" => "Slack: Send Message",
      "position" => %{"x" => 0, "y" => 0},
      "controls" => %{}
    }

  test "installs an integration once, for the workspace only", %{scope: scope} do
    assert :ok = Integrations.install(scope, "slack")
    assert :ok = Integrations.install(scope, "slack")

    assert Integrations.installed(scope) == ["slack"]
    assert Integrations.installed(user_scope_fixture()) == []
  end

  test "a viewer can't install", %{workspace: workspace} do
    viewer = user_fixture()
    member_fixture(workspace, viewer, "viewer")

    assert {:error, :forbidden} = Integrations.install(user_scope_fixture(viewer), "slack")
  end

  test "lists the node types the flows use, and the flows that use some", %{
    scope: scope,
    user: user,
    workspace: workspace
  } do
    flow_fixture(%{user: user, workspace: workspace, name: "Alerts", nodes: [slack_node()]})
    flow_fixture(%{user: user, workspace: workspace, name: "Empty"})

    assert Integrations.used_node_types(scope) == ["Slack: Send Message"]

    assert [%{name: "Alerts"}] =
             Integrations.flows_using(scope, ["Slack: Send Message", "Slack: Add Reaction"])

    assert Integrations.flows_using(scope, ["Redis: Get"]) == []
  end

  test "won't remove an integration a flow uses", %{
    scope: scope,
    user: user,
    workspace: workspace
  } do
    :ok = Integrations.install(scope, "slack")
    flow = flow_fixture(%{user: user, workspace: workspace, nodes: [slack_node()]})

    assert {:error, {:in_use, [%{id: id}]}} =
             Integrations.uninstall(scope, "slack", ["Slack: Send Message"])

    assert id == flow.id
    assert Integrations.installed(scope) == ["slack"]
  end

  test "removes an integration no flow uses", %{scope: scope} do
    :ok = Integrations.install(scope, "slack")

    assert :ok = Integrations.uninstall(scope, "slack", ["Slack: Send Message"])
    assert Integrations.installed(scope) == []
  end
end
