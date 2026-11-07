defmodule HeddleWorker.ScheduleWorker do
  @moduledoc """
  Runs every minute and starts the flows whose Schedule node is due.

  Oban's cron plugin only runs this on the leader, so several workers don't start a
  flow several times. A minute with no worker running is skipped, not made up for.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  alias Heddle.Graph
  alias HeddleCore.Executions
  alias HeddleCore.Flows
  alias HeddleCore.Flows.Schedule

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{scheduled_at: scheduled_at}) do
    now = scheduled_at || DateTime.utc_now()

    for flow <- Flows.list_flows_with_node("Schedule"),
        node <- flow |> Graph.new() |> Graph.of_type("Schedule"),
        Schedule.due?(node.controls["cron"], now) do
      start(flow, node)
    end

    :ok
  end

  defp start(flow, node) do
    input = %{"trigger" => "schedule", "node_id" => node.id}

    with {:error, reason} <- Executions.start_execution(flow, input) do
      Logger.error("Could not start scheduled flow #{flow.id}: #{inspect(reason)}")
    end
  end
end
