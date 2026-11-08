defmodule HeddleUI.PublicAPI.V1.ExecutionJSON do
  alias HeddleCore.Executions.Execution

  def index(%{executions: executions, meta: meta}) do
    %{data: Enum.map(executions, &data/1), meta: meta}
  end

  def show(%{execution: execution}) do
    %{data: data(execution)}
  end

  @doc """
  What `show/1` returns, without the context each step got: an agent reads what each
  step left in `data.output`, and the input of a step is the output of the one before.
  """
  def for_agent(%{execution: execution}) do
    %{data: data} = show(%{execution: execution})
    %{data: Map.update!(data, :logs, fn logs -> Enum.map(logs, &without_input/1) end)}
  end

  defp without_input(%{"data" => %{} = step_data} = entry),
    do: Map.put(entry, "data", Map.delete(step_data, "input"))

  defp without_input(entry), do: entry

  defp data(%Execution{} = execution) do
    %{
      id: execution.public_id,
      internal_id: execution.id,
      workflow_id: execution.flow_id,
      status: execution.status,
      input: execution.input || %{},
      result: execution.result,
      error: execution.error,
      logs: execution.logs || [],
      response: execution.response,
      waiting: waiting(execution),
      started_at: execution.started_at,
      finished_at: execution.finished_at,
      inserted_at: execution.inserted_at,
      updated_at: execution.updated_at
    }
  end

  # What is left of the run is internal, and the address to resume it is a secret
  # the flow sends where it chooses.
  defp waiting(%Execution{status: "waiting", paused: %{"wait" => wait}}) do
    %{node_id: wait["node_id"], until: wait["resume_at"], for_call: wait["call"] == true}
  end

  defp waiting(_execution), do: nil
end
