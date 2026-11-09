defmodule HeddleNodes.Nodes.SubflowTrigger do
  @moduledoc """
  Starts a flow when a Subflow node of another flow runs it.

  The run gets `result`, the Data the Subflow sent, and `caller`, with the `flow_id`,
  `flow_name` and `execution_id` of the run that called it. What the flow ends with in
  `result` goes back to the Subflow that waits for it.
  """

  use Bobbin.Node

  definition do
    %{
      name: "Subflow Trigger",
      title: "Subflow Trigger",
      category: :trigger,
      color: "bg-violet-500/15 text-violet-700 dark:text-violet-300",
      description:
        "Starts this flow when a Subflow node of another flow runs it, with what it sent in result.",
      icon: "hero-arrow-down-on-square-solid",
      inputs: [],
      outputs: [:exec],
      show: true,
      ui_fields: []
    }
  end

  @impl true
  def handler(context, _input), do: {:ok, context, "exec"}
end
