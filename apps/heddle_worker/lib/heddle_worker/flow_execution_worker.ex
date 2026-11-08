defmodule HeddleWorker.FlowExecutionWorker do
  @moduledoc """
  Oban worker responsible for running persisted flow executions.

  A job with a `wait_id` resumes a run a Wait paused, with `by` saying what ended the
  wait. Only the first job to claim the pause runs it. See `Executions.pause/2`.

  A run started from the editor has `"debug"` in its input: it takes the data pinned to
  nodes, and tells the editor about each step as it ends. A run that fails starts the
  error flow of its flow, see `Executions.start_error_flow/2`.
  """

  use Oban.Worker, queue: :executions, max_attempts: 3

  alias HeddleCore.Executions
  alias HeddleCore.Flows
  alias HeddleCore.Flows.Versions
  alias HeddleNodes.Runner

  @internal_result_keys ["flow_id", "workspace_id", "logs"]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"execution_id" => id, "wait_id" => wait_id} = args, id: job_id}) do
    case Executions.claim_resume(id, wait_id, job_id) do
      {:ok, execution} ->
        flow = execution.flow_id |> Flows.get_flow!() |> Versions.for_execution(execution)
        resumption = Map.take(args, ["by", "request"])

        flow
        |> Runner.resume(execution.paused, resumption, run_options(execution))
        |> persist(execution)

      # Something else ended this wait first.
      :error ->
        :ok
    end
  end

  def perform(%Oban.Job{args: %{"execution_id" => execution_id}}) do
    execution = Executions.get_execution!(execution_id)
    # It runs the version it was started with, whatever the flow has become since.
    flow = execution.flow_id |> Flows.get_flow!() |> Versions.for_execution(execution)

    with {:ok, running_execution} <- Executions.mark_running(execution) do
      flow
      |> run_flow(running_execution)
      |> persist(running_execution)
    end
  end

  def perform(%Oban.Job{args: args}) do
    {:error, {:missing_execution_id, args}}
  end

  defp persist({:ok, context}, execution), do: persist_success(execution, context)

  defp persist({:error, reason, node_id, context}, execution),
    do: persist_failure(execution, reason, node_id, context)

  defp persist({:wait, paused}, execution) do
    case Executions.pause(execution, paused) do
      {:ok, execution} ->
        Executions.broadcast_execution_updated(execution)
        :ok

      {:error, :unsaveable} ->
        message = "This run holds a value that can't be saved, so it can't wait."

        persist_failure(
          execution,
          message,
          get_in(paused, ["wait", "node_id"]),
          paused["context"]
        )

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp run_options(execution) do
    debug = match?(%{"debug" => true}, execution.input)

    [
      on_respond: &Executions.put_response(execution, &1),
      resume_url: Executions.resume_url(execution),
      debug: debug
    ] ++ if(debug, do: [on_step: &Executions.broadcast_step(execution.id, &1)], else: [])
  end

  defp run_flow(flow, execution) do
    opts = run_options(execution)

    case execution.input do
      %{"replay_from" => _node_id} = input ->
        Runner.run(flow, input, opts)

      %{"trigger" => "webhook", "request" => request} = input ->
        Runner.run_from_webhook(flow, request, [section: input["section_id"]] ++ opts)

      input ->
        Runner.run(flow, input, opts)
    end
  end

  defp persist_success(execution, context) do
    logs = Map.get(context, "logs", [])
    result = Map.drop(context, @internal_result_keys)

    case Executions.mark_succeeded(execution, result, %{logs: logs}) do
      {:ok, execution} ->
        Executions.broadcast_execution_updated(execution)
        :ok

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp persist_failure(execution, reason, node_id, context) do
    error =
      %{
        "message" => format_reason(reason)
      }
      |> maybe_put_node_id(node_id)

    case Executions.mark_failed(execution, error, failure_details(context)) do
      {:ok, execution} ->
        Executions.broadcast_execution_updated(execution)
        Executions.start_error_flow(execution, error)
        :ok

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  # What explains the failure. A value that can't be stored must not lose the failure.
  defp failure_details(context) do
    result = Map.drop(context, @internal_result_keys)

    case Jason.encode(result) do
      {:ok, _json} -> %{logs: Map.get(context, "logs", []), result: result}
      {:error, _reason} -> %{logs: Map.get(context, "logs", [])}
    end
  end

  defp maybe_put_node_id(error, nil), do: error
  defp maybe_put_node_id(error, node_id), do: Map.put(error, "node_id", to_string(node_id))

  # Compiler errors come with the colors of a terminal.
  defp format_reason(reason) when is_binary(reason) do
    String.replace(reason, ~r/\e\[[0-9;]*m/, "")
  end

  defp format_reason(reason), do: inspect(reason)
end
