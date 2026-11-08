defmodule HeddleWorker.FlowExecutionWorker do
  @moduledoc """
  Oban worker responsible for running persisted flow executions.
  """

  use Oban.Worker, queue: :executions, max_attempts: 3

  alias HeddleCore.Executions
  alias HeddleCore.Flows
  alias HeddleNodes.Runner

  @internal_result_keys ["flow_id", "workspace_id", "logs"]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"execution_id" => execution_id}}) do
    execution = Executions.get_execution!(execution_id)
    flow = Flows.get_flow!(execution.flow_id)

    with {:ok, running_execution} <- Executions.mark_running(execution) do
      case run_flow(flow, running_execution) do
        {:ok, context} ->
          persist_success(running_execution, context)

        {:error, reason, node_id, context} ->
          persist_failure(running_execution, reason, node_id, context)
      end
    end
  end

  def perform(%Oban.Job{args: args}) do
    {:error, {:missing_execution_id, args}}
  end

  defp run_flow(flow, execution) do
    opts = [on_respond: &Executions.put_response(execution, &1)]

    case execution.input do
      %{"trigger" => "webhook", "request" => request} ->
        Runner.run_from_webhook(flow, request, opts)

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
