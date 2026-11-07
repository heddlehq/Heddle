defmodule HeddleNodes.Nodes.Sql.RunQuery do
  use Bobbin.Node

  alias HeddleNodes.Services.Sql

  definition do
    Sql.definition(
      "Run Query",
      "Runs any statement on PostgreSQL, MySQL, MariaDB, SQL Server, SQLite or Oracle. " <>
        "{{placeholders}} go as parameters, so a value can't change the query.",
      [%{type: :textarea, name: :sql, label: "Query", default: ""}]
    )
  end

  @impl true
  def handler(context, _input) do
    Sql.run(context, fn engine, conn ->
      Sql.execute(engine, conn, context["sql"] || "", context)
    end)
  end
end
