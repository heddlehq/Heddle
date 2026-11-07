defmodule HeddleNodes.Nodes.Neo4j.RunQuery do
  use Bobbin.Node

  alias HeddleNodes.Services.Neo4j

  definition do
    Neo4j.definition(
      "Run Query",
      "Runs a Cypher query on a graph. " <>
        "{{placeholders}} go as parameters, so a value can't change the query.",
      [%{type: :textarea, name: :cypher, label: "Query", default: ""}]
    )
  end

  @impl true
  def handler(context, _input) do
    Neo4j.run(context, &Neo4j.execute(&1, context["cypher"] || "", context))
  end
end
