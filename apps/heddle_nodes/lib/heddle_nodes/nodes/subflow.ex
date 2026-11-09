defmodule HeddleNodes.Nodes.Subflow do
  @moduledoc """
  Runs another flow of the same workspace, its published version, as a step of this
  one.

  The other flow begins at its Subflow Trigger, or at its Start node when it has none,
  with `Data` as its `result` and `caller`, the flow that called it. Waiting for it,
  this node goes on through `success` with the `result` the other flow ended with, or
  through `error` with why it failed. Without waiting, it goes on at once, with the id
  of the run it started.

  A flow can't call itself, directly or through others, and a chain of calls stops at
  a few levels: see the `:subflow_client` config, `HeddleWorker.Subflow`, which runs it.
  heddle_worker is not a dependency of this app, so the client comes from the config.
  """

  use Bobbin.Node

  alias HeddleNodes.Integration

  definition do
    %{
      name: "Subflow",
      title: "Subflow",
      category: :flow_control,
      color: "bg-violet-500/15 text-violet-700 dark:text-violet-300",
      description:
        "Runs another flow of this workspace, from its Subflow Trigger, with Data as its result. Waiting for it, result is what it ended with.",
      icon: "hero-arrow-top-right-on-square-solid",
      inputs: [:exec],
      outputs: Integration.outputs(),
      show: true,
      ui_fields: [
        %{type: :flow, name: :subflow_id, label: "Flow", default: ""},
        %{type: :textarea, name: :subflow_data, label: "Data", default: "{{result}}"},
        %{
          type: :select,
          name: :subflow_mode,
          label: "Wait",
          options: [
            %{label: "Wait for it to finish", value: "wait"},
            %{label: "Start it and go on", value: "start"}
          ],
          default: "wait"
        }
      ]
    }
  end

  @impl true
  def handler(context, _input) do
    client = Application.fetch_env!(:heddle_nodes, :subflow_client)

    with {:ok, subflow_id} <- subflow_id(context),
         {:ok, data} <- data(context),
         {:ok, result} <-
           client.run(%{
             workspace_id: context["workspace_id"],
             caller_id: context["flow_id"],
             subflow_id: subflow_id,
             data: data,
             wait: context["subflow_mode"] != "start"
           }) do
      Integration.success(context, result)
    else
      {:error, message} -> Integration.failure(context, message)
    end
  end

  defp subflow_id(context) do
    case context |> Integration.field("subflow_id") |> String.trim() do
      "" -> {:error, "Pick the flow to run."}
      id -> {:ok, id}
    end
  end

  # Empty Data sends nothing.
  defp data(context) do
    case String.trim(context["subflow_data"] || "") do
      "" -> {:ok, nil}
      _data -> Integration.json(context, "subflow_data")
    end
  end
end
