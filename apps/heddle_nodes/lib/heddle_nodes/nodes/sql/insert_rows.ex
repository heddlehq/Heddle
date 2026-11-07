defmodule HeddleNodes.Nodes.Sql.InsertRows do
  use Bobbin.Node

  alias HeddleNodes.Services.Sql

  definition do
    Sql.definition(
      "Insert Rows",
      "Adds one row or a list of them, from column to value. All of them or none go in.",
      [Sql.table_field(), Sql.rows_field()]
    )
  end

  @impl true
  def handler(context, _input) do
    Sql.run(context, fn engine, conn ->
      with {:ok, table} <- Sql.table(engine, context),
           {:ok, columns, rows} <- Sql.rows(context) do
        Sql.write_rows(engine, conn, columns, rows, &engine.insert(table, columns, &1))
      end
    end)
  end
end
