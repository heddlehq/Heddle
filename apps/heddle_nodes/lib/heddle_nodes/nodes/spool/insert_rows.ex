defmodule HeddleNodes.Nodes.Spool.InsertRows do
  use Bobbin.Node

  alias HeddleNodes.Services.Spool

  definition do
    Spool.definition(
      "Insert Rows",
      "Adds one row or a list of them to a Spool table, from column to value. All of them or none go in.",
      [Spool.rows_field()]
    )
  end

  @impl true
  def handler(context, _input) do
    Spool.run(context, fn client, workspace_id, table ->
      with {:ok, rows} <- Spool.rows(context) do
        client.insert(workspace_id, table, rows)
      end
    end)
  end
end
