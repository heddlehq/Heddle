defmodule HeddleNodes.Nodes.Spool.UpsertRows do
  use Bobbin.Node

  alias HeddleNodes.Integration
  alias HeddleNodes.Services.Spool

  definition do
    Spool.definition(
      "Upsert Rows",
      "Adds rows to a Spool table, or changes the row that has the same value in the key column.",
      [
        %{type: :text, name: :key_column, label: "Key column", default: ""},
        Spool.rows_field()
      ]
    )
  end

  @impl true
  def handler(context, _input) do
    Spool.run(context, fn client, workspace_id, table ->
      with {:ok, rows} <- Spool.rows(context) do
        client.upsert(workspace_id, table, Integration.field(context, "key_column"), rows)
      end
    end)
  end
end
