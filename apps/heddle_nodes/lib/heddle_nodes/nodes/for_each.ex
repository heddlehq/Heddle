defmodule HeddleNodes.Nodes.ForEach do
  use Bobbin.Node

  alias HeddleNodes.Template

  # Every iteration adds to the run's logs, which are saved as one row.
  @max_items 10_000

  definition do
    %{
      name: "For Each",
      title: "For Each",
      category: :flow_control,
      color: "bg-amber-500/15 text-amber-700 dark:text-amber-300",
      description:
        "Runs the item branch once per item, with the item in result and index in a variable. The done branch gets the results.",
      icon: "hero-arrow-path-rounded-square-solid",
      inputs: [:exec],
      outputs: ["item", "done"],
      show: true,
      ui_fields: [
        %{
          type: :text,
          name: :items,
          label: "List",
          default: "result"
        }
      ]
    }
  end

  def max_items, do: @max_items

  @impl true
  def handler(context, _input) do
    path = context["items"] || "result"

    case Template.fetch(context, path) do
      items when is_list(items) and length(items) > @max_items ->
        {:error, "#{path} has more than #{@max_items} items."}

      items when is_list(items) ->
        {:each, items}

      _other ->
        {:error, "#{path} is not a list."}
    end
  end
end
