defmodule HeddleNodes.Nodes.Sql.DescribeTable do
  use Bobbin.Node

  alias HeddleNodes.Services.Sql

  definition do
    Sql.definition(
      "Describe Table",
      "Returns the columns of a table, with their types.",
      [Sql.table_field()]
    )
  end

  @impl true
  def handler(context, _input) do
    Sql.run(context, fn engine, conn ->
      with {:ok, table} <- Sql.table(engine, context) do
        {sql, params} = engine.columns(table)

        with {:ok, %{"rows" => rows}} <- Sql.query(engine, conn, sql, params) do
          {:ok, %{"columns" => Enum.map(rows, &read_nullable/1)}}
        end
      end
    end)
  end

  # Some engines have no boolean, so this comes as 1 or 0.
  defp read_nullable(%{"nullable" => nullable} = column) do
    %{column | "nullable" => nullable in [true, 1]}
  end
end
