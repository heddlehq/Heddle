defmodule HeddleNodes.Nodes.ErrorTrigger do
  @moduledoc """
  Starts a flow when a run of another flow fails, for flows picked as the error flow of
  others in their settings.

  The run gets `error`, with the `message` and the `node_id`, `node_label` and
  `node_type` of the step that failed, and `execution`, with the `id`, `flow_id`,
  `flow_name` and `url` of the run that failed.
  """

  use Bobbin.Node

  definition do
    %{
      name: "Error Trigger",
      title: "Error Trigger",
      category: :trigger,
      color: "bg-red-500/15 text-red-700 dark:text-red-300",
      description:
        "Starts this flow when a run of a flow that picked it as its error flow fails, with the error and the run.",
      icon: "hero-exclamation-triangle-solid",
      inputs: [],
      outputs: [:exec],
      show: true,
      ui_fields: []
    }
  end

  @impl true
  def handler(context, _input), do: {:ok, context, "exec"}
end
