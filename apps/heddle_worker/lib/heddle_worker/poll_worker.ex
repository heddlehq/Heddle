defmodule HeddleWorker.PollWorker do
  @moduledoc """
  Runs every minute and calls the trigger nodes of integrations that are due, each
  every few minutes as its manifest says. The flow starts once for each new item, with
  the item as `item`, which the trigger node passes on as `result`.

  Like `HeddleWorker.ScheduleWorker`, Oban's cron plugin only runs this on the leader.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  alias Heddle.Graph
  alias HeddleCore.Executions
  alias HeddleCore.Flows
  alias HeddleCore.Integrations.Polls
  alias HeddleNodes.Manifests

  require Logger

  # So a service that returns everything as new can't start a flood of runs.
  @max_runs 50

  @impl Oban.Worker
  def perform(%Oban.Job{scheduled_at: scheduled_at}) do
    now = scheduled_at || DateTime.utc_now()

    for trigger <- Manifests.poll_triggers(),
        flow <- Flows.list_flows_with_node(trigger.type),
        node <- flow |> Graph.new() |> Graph.of_type(trigger.type) do
      poll = Polls.get(flow.id, node.id)
      if Polls.due?(poll, trigger.trigger.poll.every, now), do: poll(flow, node, trigger, now)
    end

    :ok
  end

  defp poll(flow, node, trigger, now) do
    context = Map.merge(node.controls || %{}, %{"workspace_id" => flow.workspace_id})

    case Manifests.poll(trigger.manifest, trigger.trigger.name, context) do
      {:ok, items} ->
        flow.id
        |> Polls.record(node.id, items, now)
        |> Enum.take(-@max_runs)
        |> Enum.each(&start(flow, node, &1))

      {:error, message} ->
        Logger.warning("#{trigger.type} in flow #{flow.id} failed: #{message}")
        Polls.failed(flow.id, node.id, message, now)
    end
  end

  defp start(flow, node, item) do
    input = %{"trigger" => "poll", "node_id" => node.id, "item" => item}

    with {:error, reason} <- Executions.start_execution(flow, input) do
      Logger.error("Could not start flow #{flow.id} for a new item: #{inspect(reason)}")
    end
  end
end
