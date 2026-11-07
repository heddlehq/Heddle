defmodule HeddleNodes.Nodes.Cassandra.RunQuery do
  use Bobbin.Node

  alias HeddleNodes.Services.Cassandra

  definition do
    Cassandra.definition(
      "Run Query",
      "Runs a CQL statement on Cassandra or ScyllaDB, a BATCH included. " <>
        "{{placeholders}} go as parameters, so a value can't change the query.",
      [%{type: :textarea, name: :cql, label: "Query", default: ""}]
    )
  end

  @impl true
  def handler(context, _input) do
    Cassandra.run(context, &Cassandra.execute(&1, context["cql"] || "", context))
  end
end
