defmodule HeddleNodes.Nodes.Schedule do
  use Bobbin.Node

  definition do
    %{
      name: "Schedule",
      title: "Schedule",
      category: :trigger,
      color: "bg-emerald-500/15 text-emerald-700 dark:text-emerald-300",
      description: "Starts the flow on a schedule, written as a cron expression in UTC.",
      icon: "hero-clock-solid",
      inputs: [],
      outputs: [:exec],
      show: true,
      ui_fields: [
        %{
          type: :text,
          name: :cron,
          label: "Cron (UTC)",
          default: "0 9 * * *"
        }
      ]
    }
  end

  @impl true
  def handler(context, _input), do: {:ok, context, :exec}
end
