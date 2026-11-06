defmodule HeddleNodes.Nodes.Start do
  use FusionKit.Node

  definition do
    %{
      name: "Start",
      title: "Start",
      category: :flow_control,
      color: "bg-amber-500/15 text-amber-700 dark:text-amber-300",
      description: "Starts manual flow execution and passes the initial context forward.",
      icon: "hero-play-solid",
      inputs: [],
      outputs: ["exec"],
      show: true,
      ui_fields: []
    }
  end

  @impl true
  def handler(context, _input) do
    {:ok, context, "exec"}
  end
end
