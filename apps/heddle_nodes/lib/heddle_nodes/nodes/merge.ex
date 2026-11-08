defmodule HeddleNodes.Nodes.Merge do
  @moduledoc """
  Joins the branches that lead to it into one.

  The runner holds each branch that arrives, and calls this once every connection to
  the node has arrived, or once nothing else in the run is left to do, with what
  each branch had in `result`, in the order they arrived. See `HeddleNodes.Runner`.
  """

  use Bobbin.Node

  definition do
    %{
      name: "Merge",
      title: "Merge",
      category: :flow_control,
      color: "bg-amber-500/15 text-amber-700 dark:text-amber-300",
      description:
        "Waits for every branch connected to it, then goes on once with their results together.",
      icon: "hero-arrows-pointing-in-solid",
      inputs: [:exec],
      outputs: [:exec],
      show: true,
      ui_fields: [
        %{
          type: :select,
          name: :combine,
          label: "Combine",
          options: [
            %{label: "List of results", value: "list"},
            %{label: "Join lists", value: "concat"},
            %{label: "Merge objects", value: "objects"}
          ],
          default: "list"
        }
      ]
    }
  end

  @impl true
  def handler(%{"result" => results} = context, _input) when is_list(results) do
    {:result, combine(context["combine"], results)}
  end

  def handler(context, _input), do: {:result, context["result"]}

  defp combine("concat", results), do: Enum.flat_map(results, &List.wrap/1)

  defp combine("objects", results) do
    results |> Enum.filter(&is_map/1) |> Enum.reduce(%{}, &Map.merge(&2, &1))
  end

  defp combine(_list, results), do: results
end
