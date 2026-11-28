defmodule HeddleWorker.PackageRuns do
  @moduledoc """
  Starts the runs a package asks for, for `start_runs/1`, `cancel_run/2` and
  `resume_run/4` of `Bobbin.Host`, through the `:runs_client` config of
  `:heddle_nodes`.

  A package's trigger node is the start of a flow, like a Subflow Trigger. Every
  published flow of the workspace with that trigger, whose controls hold the ones
  asked for, starts at it, with `"trigger" => "package"`, the data as `result`, and
  `caller`. Only flows of the run's workspace start, the one the runner pins in the
  context.

  `caller` keeps the chain of flows that led to a run, as for a Subflow, and a chain
  stops at `@max_depth`, so flows that start each other can't go on forever. A flow can
  start itself, like an agent that writes to itself. A run for later starts a chain of
  its own: what waited can't loop.
  """

  require Logger

  alias Heddle.Graph
  alias HeddleCore.Executions
  alias HeddleCore.Flows

  @max_depth 8
  @current {HeddleWorker.Subflow, :current}

  @doc "Starts the runs `request` asks for, see `Bobbin.Host`."
  def start_runs(%{workspace_id: workspace_id, node_type: type} = request)
      when not is_nil(workspace_id) and is_binary(type) do
    current = Process.get(@current, %{execution_id: nil, chain: []})
    at = request[:at]
    chain = if at, do: [], else: current.chain ++ List.wrap(current_flow_id())

    if length(chain) >= @max_depth do
      {:error, "Flows can start each other #{@max_depth} levels deep at most."}
    else
      runs =
        for flow <- Flows.list_flows_with_node(type, workspace_id),
            node <- flow |> Graph.new() |> Graph.of_type(type),
            matches?(node.controls, request[:match] || %{}),
            {:ok, run} <- [start(flow, node, request, caller(current, chain))],
            do: run

      {:ok, runs}
    end
  end

  def start_runs(_request), do: {:error, "This run has no workspace to start flows in."}

  @doc "Cancels a run that hasn't begun, see `Bobbin.Host`."
  def cancel_run(workspace_id, run_id), do: Executions.cancel_queued(workspace_id, run_id)

  @doc "Resumes a run a package's node paused, see `Bobbin.Host`."
  def resume_run(workspace_id, run_id, key, value),
    do: Executions.resume_run(workspace_id, run_id, key, value)

  defp start(flow, node, request, caller) do
    input = %{
      "trigger" => "package",
      "node_id" => node.id,
      "result" => request[:data] || %{},
      "caller" => caller
    }

    case Executions.start_execution(flow, input, lane: request[:lane], at: request[:at]) do
      {:ok, execution} ->
        {:ok, %{"run_id" => execution.public_id, "flow_id" => flow.id, "flow_name" => flow.name}}

      {:error, reason} ->
        Logger.error("Could not start flow #{flow.id} at #{node.type}: #{inspect(reason)}")
        :error
    end
  end

  defp matches?(controls, match) do
    Enum.all?(match, fn {key, value} ->
      text(Map.get(controls || %{}, to_string(key))) == text(value)
    end)
  end

  defp text(nil), do: ""
  defp text(value), do: value |> to_string() |> String.trim()

  defp caller(current, chain), do: %{"execution_id" => current.execution_id, "chain" => chain}

  # The flow of the run asking, from the run as it was created.
  defp current_flow_id do
    case Process.get(@current) do
      %{execution_id: public_id} when is_binary(public_id) ->
        case Executions.get_execution_by_public_id!(public_id) do
          %{flow_id: flow_id} -> flow_id
        end

      _none ->
        nil
    end
  rescue
    Ecto.NoResultsError -> nil
  end
end
