defmodule HeddleNodes.Nodes.Spool.FindRows do
  use Bobbin.Node

  alias HeddleNodes.Integration
  alias HeddleNodes.Services.Spool

  @default_limit 100

  definition do
    Spool.definition(
      "Find Rows",
      "Reads the rows of a Spool table that match a filter, in order.",
      [
        Spool.filter_field(),
        %{type: :text, name: :order_by, label: "Order by", default: "created_at desc"},
        %{type: :text, name: :limit, label: "Limit", default: "100"},
        %{type: :text, name: :offset, label: "Skip", default: "0"}
      ]
    )
  end

  @impl true
  def handler(context, _input) do
    Spool.run(context, fn client, workspace_id, table ->
      with {:ok, filter} <- Spool.filter(context) do
        client.find(workspace_id, table, filter,
          order: Integration.field(context, "order_by"),
          limit: Integration.number(context, "limit", @default_limit),
          offset: offset(context)
        )
      end
    end)
  end

  defp offset(context) do
    case context |> Integration.field("offset") |> String.trim() |> Integer.parse() do
      {offset, ""} when offset > 0 -> offset
      _other -> 0
    end
  end
end
