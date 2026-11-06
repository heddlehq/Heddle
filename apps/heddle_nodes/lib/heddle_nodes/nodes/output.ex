defmodule HeddleNodes.Nodes.Output do
  use Bobbin.Node

  definition do
    %{
      name: "Output",
      title: "Output",
      category: :flow_control,
      color: "bg-amber-500/15 text-amber-700 dark:text-amber-300",
      description: "Finishes the flow and returns the final execution context.",
      icon: "hero-flag-solid",
      inputs: [:exec],
      outputs: [],
      show: true,
      ui_fields: [
        %{
          type: :text,
          name: :status,
          label: "Final Status",
          default: "success"
        }
      ]
    }
  end

  @impl true
  def handler(context, _input) do
    {:ok, context, "exec"}
  end
end
