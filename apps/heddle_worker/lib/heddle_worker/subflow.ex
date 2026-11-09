defmodule HeddleWorker.Subflow do
  @moduledoc """
  Runs the flow a Subflow node picked, for `HeddleNodes.Nodes.Subflow`, through the
  `:subflow_client` config of `:heddle_nodes`.

  The other flow runs as a run of its own, of its published version, so it shows in
  its runs with its steps, and its error flow starts when it fails. It begins at its
  Subflow Trigger with `"trigger" => "subflow"`, the Data as `result`, and `caller`.

  Waiting for it, it runs in a task of this worker, while the Subflow waits: it holds
  no other job of the queue, so callers waiting for each other can't use them all up.
  Without waiting, it is queued like any other run.

  Only flows of the run's workspace can be called, the one the runner pins in the
  context. `caller` keeps the chain of flows that led to a run, and it is read from
  the run as it was created, not from its context, which a flow can change. A flow
  already in the chain can't be called again, and a chain stops at `@max_depth`.
  """

  alias HeddleCore.Executions
  alias HeddleCore.Executions.Execution
  alias HeddleCore.Flows
  alias HeddleCore.Flows.Flow
  alias HeddleWorker.FlowExecutionWorker

  @max_depth 8
  @current {__MODULE__, :current}

  @doc """
  Remembers, for the Subflow nodes of the run this process is about to run, which run
  it is and which flows led to it. `FlowExecutionWorker` calls it.
  """
  def enter(%Execution{} = execution) do
    chain =
      case execution.input do
        %{"caller" => %{"chain" => chain}} when is_list(chain) -> chain
        _input -> []
      end

    Process.put(@current, %{execution_id: execution.public_id, chain: chain})
  end

  @doc """
  Runs the flow `subflow_id` of `workspace_id` with `data`. Returns `{:ok, result}`:
  with `wait: true` what the flow ended with in `result`, and otherwise the run it
  started. Returns `{:error, message}` when it can't run, or failed.
  """
  def run(%{workspace_id: workspace_id, subflow_id: subflow_id} = call) do
    current = Process.get(@current, %{execution_id: nil, chain: []})
    chain = current.chain ++ List.wrap(call[:caller_id])

    with {:ok, flow} <- fetch(workspace_id, subflow_id),
         :ok <- check_chain(flow, chain),
         {:ok, version_id} <- version(flow) do
      input = %{
        "trigger" => "subflow",
        "result" => call[:data],
        "caller" => caller(call[:caller_id], current.execution_id, chain)
      }

      if call[:wait] == false,
        do: start(flow, input),
        else: run_and_wait(flow, version_id, input)
    end
  end

  defp fetch(workspace_id, id) do
    with {id, ""} <- Integer.parse(to_string(id)),
         %Flow{workspace_id: ^workspace_id} = flow when not is_nil(workspace_id) <-
           Flows.get_flow(id) do
      {:ok, flow}
    else
      _other -> {:error, "The flow picked isn't in this workspace any more."}
    end
  end

  defp check_chain(%Flow{id: id, name: name}, chain) do
    cond do
      id in chain ->
        {:error, "#{name} is already running in this chain of flows, so it would call itself."}

      length(chain) >= @max_depth ->
        {:error, "Flows can call each other #{@max_depth} levels deep at most."}

      true ->
        :ok
    end
  end

  defp version(%Flow{} = flow) do
    case Executions.version_id(flow) do
      {:ok, version_id} ->
        {:ok, version_id}

      {:error, :not_published} ->
        {:error, "#{flow.name} isn't published, so it has nothing to run."}
    end
  end

  defp caller(nil, execution_id, chain),
    do: %{"execution_id" => execution_id, "chain" => chain}

  defp caller(flow_id, execution_id, chain) do
    %{
      "flow_id" => flow_id,
      "flow_name" => flow_id |> Flows.get_flow() |> name(),
      "execution_id" => execution_id,
      "chain" => chain
    }
  end

  defp name(%Flow{name: name}), do: name
  defp name(nil), do: nil

  defp start(flow, input) do
    case Executions.start_execution(flow, input) do
      {:ok, execution} ->
        {:ok,
         %{
           "execution_id" => execution.public_id,
           "flow_id" => flow.id,
           "flow_name" => flow.name
         }}

      {:error, _reason} ->
        {:error, "#{flow.name} couldn't be started."}
    end
  end

  defp run_and_wait(flow, version_id, input) do
    with {:ok, execution} <-
           Executions.create_execution(%{
             flow_id: flow.id,
             flow_version_id: version_id,
             input: input
           }) do
      task =
        Task.Supervisor.async_nolink(HeddleWorker.TaskSupervisor, fn ->
          FlowExecutionWorker.perform(%Oban.Job{args: %{"execution_id" => execution.id}})
        end)

      case Task.yield(task, :infinity) do
        {:ok, _done} ->
          outcome(flow, Executions.get_execution!(execution.id))

        {:exit, reason} ->
          message = "#{flow.name} stopped: #{Exception.format_exit(reason)}"
          Executions.mark_failed(Executions.get_execution!(execution.id), message)
          {:error, message}
      end
    else
      {:error, _changeset} -> {:error, "#{flow.name} couldn't be started."}
    end
  end

  defp outcome(_flow, %Execution{status: "succeeded", result: result}),
    do: {:ok, (result || %{})["result"]}

  defp outcome(flow, %Execution{status: "failed", error: error}),
    do: {:error, "#{flow.name} failed: #{(error || %{})["message"]}"}

  defp outcome(flow, %Execution{status: "waiting"}) do
    {:error,
     "#{flow.name} paused at a Wait, so this flow can't wait for it. Pick Start it and go on."}
  end

  defp outcome(flow, %Execution{status: status}),
    do: {:error, "#{flow.name} ended #{status}."}
end
