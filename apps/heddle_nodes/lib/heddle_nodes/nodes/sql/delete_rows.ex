defmodule HeddleNodes.Nodes.Sql.DeleteRows do
  use Bobbin.Node

  alias HeddleNodes.Services.Sql

  definition do
    Sql.definition(
      "Delete Rows",
      "Deletes the rows that match. To delete every row, write 1 = 1 in Where.",
      [Sql.table_field(), Sql.where_field()]
    )
  end

  @impl true
  def handler(context, _input) do
    Sql.run(context, fn engine, conn ->
      with {:ok, table} <- Sql.table(engine, context),
           {:ok, where} <- Sql.required_where(context),
           {:ok, where, params} <- Sql.bind(engine, where, context) do
        Sql.query(engine, conn, "DELETE FROM #{table} WHERE #{where}", params)
      end
    end)
  end
end
