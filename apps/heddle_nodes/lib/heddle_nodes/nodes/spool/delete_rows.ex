defmodule HeddleNodes.Nodes.Spool.DeleteRows do
  use Bobbin.Node

  alias HeddleNodes.Services.Spool

  definition do
    Spool.definition(
      "Delete Rows",
      "Deletes the rows of a Spool table that match a filter.",
      [%{Spool.filter_field() | default: ~s({"id": "{{result.id}}"})}]
    )
  end

  @impl true
  def handler(context, _input) do
    Spool.run(context, fn client, workspace_id, table ->
      with {:ok, filter} <- Spool.filter(context) do
        client.delete(workspace_id, table, filter)
      end
    end)
  end
end
