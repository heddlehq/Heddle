defmodule HeddleNodes.Nodes.Spool.UpdateRows do
  use Bobbin.Node

  alias HeddleNodes.Services.Spool

  definition do
    Spool.definition(
      "Update Rows",
      "Changes the rows of a Spool table that match a filter. A null clears a column.",
      [
        %{Spool.filter_field() | default: ~s({"id": "{{result.id}}"})},
        %{type: :textarea, name: :values, label: "Values (JSON)", default: ""}
      ]
    )
  end

  @impl true
  def handler(context, _input) do
    Spool.run(context, fn client, workspace_id, table ->
      with {:ok, filter} <- Spool.filter(context),
           {:ok, values} <- Spool.values(context, "values") do
        client.update(workspace_id, table, filter, values)
      end
    end)
  end
end
