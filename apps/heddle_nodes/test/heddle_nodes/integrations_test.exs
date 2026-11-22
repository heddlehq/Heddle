defmodule HeddleNodes.IntegrationsTest do
  use ExUnit.Case, async: true

  alias HeddleNodes.Integrations

  test "holds every action of a service, and none of the core" do
    ids = Enum.map(Integrations.all(), & &1.id)

    assert "slack" in ids
    assert "google_sheets" in ids
    assert "mongodb" in ids
    assert "sql" in ids
    refute "spool" in ids
    assert ids == Enum.uniq(ids)

    slack = Integrations.get("slack")
    assert slack.title == "Slack"
    assert length(slack.nodes) == 7
    assert Enum.all?(slack.nodes, &String.starts_with?(&1.name, "Slack: "))
  end

  test "tells which integration a node belongs to" do
    assert Integrations.integration_of("Slack: Send Message") == "slack"
    assert Integrations.integration_of("SQL: Run Query") == "sql"
    assert Integrations.integration_of("HTTP Request") == nil
    assert Integrations.integration_of("Spool: Find Rows") == nil
    assert Integrations.integration_of("Nothing") == nil
  end

  test "a workspace has what it installed and what its flows use" do
    installed = Integrations.installed_ids(["redis"], ["Slack: Send Message", "HTTP Request"])

    assert MapSet.equal?(installed, MapSet.new(["redis", "slack"]))
  end

  test "core nodes are always available, the others once installed" do
    http = HeddleNodes.Nodes.get_node("HTTP Request")
    slack = HeddleNodes.Nodes.get_node("Slack: Send Message")

    assert Integrations.available?(http, MapSet.new())
    refute Integrations.available?(slack, MapSet.new())
    assert Integrations.available?(slack, MapSet.new(["slack"]))
  end
end
