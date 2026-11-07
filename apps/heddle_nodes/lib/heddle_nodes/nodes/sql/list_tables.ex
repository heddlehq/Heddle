defmodule HeddleNodes.Nodes.Sql.ListTables do
  use Bobbin.Node

  alias HeddleNodes.Services.Sql

  definition do
    Sql.definition("List Tables", "Returns the names of the tables of the database.", [])
  end

  @impl true
  def handler(context, _input) do
    Sql.run(context, fn engine, conn ->
      {sql, params} = engine.tables()

      with {:ok, %{"rows" => rows}} <- Sql.query(engine, conn, sql, params) do
        {:ok, %{"tables" => Enum.map(rows, & &1["name"])}}
      end
    end)
  end
end
