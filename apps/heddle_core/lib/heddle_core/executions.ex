defmodule HeddleCore.Executions do
  @moduledoc """
  Boundary for persisted workflow executions.
  """

  import Ecto.Query, warn: false

  alias HeddleCore.Executions.Execution
  alias HeddleCore.Flows.Flow
  alias HeddleCore.Pagination
  alias HeddleCore.Repo

  @flow_execution_worker "HeddleWorker.FlowExecutionWorker"
  @response_channel :webhook_responses
  @response_timeout :timer.seconds(30)
  @await_timeout to_timeout(minute: 2)
  @response_poll 250
  @public_id_retry_attempts 8
  @public_id_first_words ~w(blue bright calm clear crisp fresh green lean quiet rapid sharp steady swift)
  @public_id_middle_words ~w(axis beacon bridge circuit engine gate grid matrix orbit pulse signal vector)
  @public_id_last_words ~w(channel flow frame path relay route run stream trace vault wave)
  @public_id_suffix_alphabet ~c"23456789abcdefghjkmnpqrstuvwxyz"

  def list_executions do
    Repo.all(from e in Execution, order_by: [desc: e.inserted_at], preload: [:flow])
  end

  def list_executions_for_flow(%Flow{id: flow_id}), do: list_executions_for_flow(flow_id)

  def list_executions_for_flow(flow_id) do
    Repo.all(
      from e in Execution,
        where: e.flow_id == ^flow_id,
        order_by: [desc: e.inserted_at],
        preload: [:flow]
    )
  end

  def list_executions_for_flow_page(flow_or_id, opts \\ %{})

  def list_executions_for_flow_page(%Flow{id: flow_id}, opts),
    do: list_executions_for_flow_page(flow_id, opts)

  def list_executions_for_flow_page(flow_id, opts) do
    opts
    |> Map.new()
    |> Map.put(:workflow_id, flow_id)
    |> list_executions_page()
  end

  def list_executions_page(opts \\ %{}) do
    Execution
    |> filter_by_workflow_id(opts)
    |> filter_by_status(opts)
    |> filter_by_inserted_after(opts)
    |> filter_by_inserted_before(opts)
    |> order_by([e], desc: e.inserted_at)
    |> preload([:flow])
    |> Pagination.paginate(Repo, opts)
  end

  def get_execution!(id) do
    Execution
    |> Repo.get!(id)
    |> Repo.preload(:flow)
  end

  def get_execution_by_public_id!(public_id) do
    Execution
    |> Repo.get_by!(public_id: public_id)
    |> Repo.preload(:flow)
  end

  def get_execution_by_flow_and_public_id(flow_id, public_id) do
    Execution
    |> Repo.get_by(flow_id: flow_id, public_id: public_id)
    |> Repo.preload(:flow)
  end

  def subscribe_to_execution(%Execution{id: execution_id}) do
    subscribe_to_execution(execution_id)
  end

  def subscribe_to_execution(execution_id) do
    Phoenix.PubSub.subscribe(HeddleCore.PubSub, execution_topic(execution_id))
  end

  def broadcast_execution_updated(%Execution{} = execution) do
    execution = Repo.preload(execution, :flow)

    Phoenix.PubSub.broadcast(
      HeddleCore.PubSub,
      execution_topic(execution.id),
      {:execution_updated, execution}
    )

    :ok
  end

  def create_execution(attrs \\ %{}) do
    attrs =
      attrs
      |> Map.new()
      |> Map.put_new(:status, "queued")
      |> Map.put_new(:input, %{})
      |> Map.put_new(:logs, [])

    if public_id_present?(attrs) do
      insert_execution(attrs)
    else
      insert_with_public_id(attrs, @public_id_retry_attempts)
    end
  end

  @doc """
  Creates an execution of `flow` with `input` and queues it.
  """
  def start_execution(%Flow{id: flow_id}, input) do
    with {:ok, %Execution{} = execution} <- create_execution(%{flow_id: flow_id, input: input}),
         {:ok, _job} <- enqueue_execution(execution) do
      {:ok, execution}
    end
  end

  @doc """
  Builds the input of a run that behaves as if `request` had reached the Webhook node.

  `request` takes `"body"`, and optionally `"method"`, `"headers"` and `"query_params"`.
  """
  def webhook_input(request) do
    defaults = %{"method" => "POST", "headers" => %{}, "query_params" => %{}, "path" => "/test"}

    %{"trigger" => "webhook", "request" => Map.merge(defaults, request)}
  end

  @doc """
  Runs `flow` with `input` and waits for it to finish.

  Returns `{:ok, execution}` whether the run succeeded or failed, and
  `{:error, :timeout}` if it takes longer than `timeout`.
  """
  def start_and_await(%Flow{id: flow_id}, input, timeout \\ @await_timeout) do
    with {:ok, %Execution{} = execution} <- create_execution(%{flow_id: flow_id, input: input}) do
      :ok = subscribe_to_execution(execution)

      with {:ok, _job} <- enqueue_execution(execution) do
        await_finish(execution.id, timeout)
      end
    end
  end

  defp await_finish(id, timeout) do
    receive do
      {:execution_updated, %Execution{id: ^id, status: status} = execution}
      when status in ["succeeded", "failed"] ->
        {:ok, execution}
    after
      timeout -> {:error, :timeout}
    end
  end

  @doc """
  Saves what a Respond to Webhook node answered, for the call waiting on it.

  The answer goes through the database because the call can be on another node, and
  a Postgres notification only carries 8 KB.
  """
  def put_response(%Execution{id: id}, response) when is_map(response) do
    {1, nil} =
      Repo.update_all(from(e in Execution, where: e.id == ^id), set: [response: response])

    with name when not is_nil(name) <- running_oban() do
      Oban.Notifier.notify(name, @response_channel, %{id: id})
    end

    :ok
  end

  @doc """
  Waits for a run to answer its webhook.

  Returns `{:ok, response}`, or `{:error, reason}` with `:failed`, `:no_response` when
  the run ended without answering, or `:timeout`. The notification only makes this
  quicker: it also reads the row every `:poll` ms, so a lost one costs nothing.

  It runs in a task because the connection's process outlives the request, and the
  notifications must not reach it.
  """
  def await_response(%Execution{id: id}, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @response_timeout)
    poll = Keyword.get(opts, :poll, @response_poll)

    fn ->
      if Oban.whereis(oban_name()), do: Oban.Notifier.listen(oban_name(), @response_channel)
      wait_for_response(id, System.monotonic_time(:millisecond) + timeout, poll)
    end
    |> Task.async()
    |> Task.await(:infinity)
  end

  defp wait_for_response(id, deadline, poll) do
    query = from e in Execution, where: e.id == ^id, select: {e.status, e.response}

    case Repo.one(query) do
      {_status, %{} = response} ->
        {:ok, response}

      {"failed", _response} ->
        {:error, :failed}

      {"succeeded", _response} ->
        {:error, :no_response}

      _still_going ->
        remaining = deadline - System.monotonic_time(:millisecond)

        if remaining <= 0 do
          {:error, :timeout}
        else
          receive do
            {:notification, @response_channel, %{"id" => ^id}} -> :ok
          after
            min(poll, remaining) -> :ok
          end

          wait_for_response(id, deadline, poll)
        end
    end
  end

  # The UI and the worker each run their own Oban, under different names.
  defp running_oban, do: Enum.find([oban_name(), Oban], &Oban.whereis/1)

  def enqueue_execution(%Execution{} = execution) do
    %{execution_id: execution.id}
    |> Oban.Job.new(queue: :executions, worker: @flow_execution_worker, max_attempts: 3)
    |> then(&Oban.insert(running_oban() || oban_name(), &1))
  end

  @doc """
  Saves a flow's graph and enqueues a manual execution for it.

  Orchestrates the three steps the editor's "run" button performs — persist the
  graph, create the execution record, enqueue the Oban job — so the LiveView
  doesn't have to nest them.

  Returns `{:ok, %{flow: flow, execution: execution}}` on success.

  On failure returns `{:error, stage, context}`, where `stage` is one of
  `:save`, `:create` or `:enqueue`, and `context` is a map carrying the
  `:reason` plus any partial results already produced (`:flow` once the graph
  is saved, `:execution` once the record is created) so the caller can still
  reflect them in the UI.
  """
  def save_and_run(scope, %Flow{} = flow, data, input \\ %{"trigger" => "manual"}) do
    with {:ok, saved_flow} <- save_flow(scope, flow, data),
         {:ok, execution} <- create_run(saved_flow, input),
         {:ok, _job} <- enqueue_run(saved_flow, execution) do
      {:ok, %{flow: saved_flow, execution: execution}}
    end
  end

  defp save_flow(scope, flow, data) do
    case HeddleCore.Flows.update_flow(scope, flow, data) do
      {:ok, saved_flow} -> {:ok, saved_flow}
      {:error, reason} -> {:error, :save, %{reason: reason}}
    end
  end

  defp create_run(saved_flow, input) do
    case create_execution(%{flow_id: saved_flow.id, input: input}) do
      {:ok, execution} -> {:ok, execution}
      {:error, reason} -> {:error, :create, %{reason: reason, flow: saved_flow}}
    end
  end

  defp enqueue_run(saved_flow, execution) do
    case enqueue_execution(execution) do
      {:ok, job} ->
        {:ok, job}

      {:error, reason} ->
        {:error, :enqueue, %{reason: reason, flow: saved_flow, execution: execution}}
    end
  end

  defp oban_name do
    Application.get_env(:heddle_core, :oban_name, HeddleCore.Oban)
  end

  def update_execution(%Execution{} = execution, attrs) do
    execution
    |> Execution.changeset(attrs)
    |> Repo.update()
  end

  def change_execution(%Execution{} = execution, attrs \\ %{}) do
    Execution.changeset(execution, attrs)
  end

  def mark_running(%Execution{} = execution, attrs \\ %{}) do
    execution
    |> Execution.changeset(
      attrs
      |> Map.new()
      |> Map.merge(%{
        status: "running",
        started_at: timestamp()
      })
    )
    |> Repo.update()
  end

  def mark_succeeded(%Execution{} = execution, result, attrs \\ %{}) do
    execution
    |> Execution.changeset(
      attrs
      |> Map.new()
      |> Map.merge(%{
        status: "succeeded",
        result: normalize_map(result),
        error: nil,
        finished_at: timestamp()
      })
    )
    |> Repo.update()
  end

  def mark_failed(%Execution{} = execution, error, attrs \\ %{}) do
    execution
    |> Execution.changeset(
      attrs
      |> Map.new()
      |> Map.merge(%{
        status: "failed",
        error: normalize_error(error),
        finished_at: timestamp()
      })
    )
    |> Repo.update()
  end

  def append_log(%Execution{} = execution, log_entry) when is_map(log_entry) do
    update_execution(execution, %{logs: execution.logs ++ [log_entry]})
  end

  def append_log(%Execution{} = execution, log_entry) do
    append_log(execution, %{"message" => to_string(log_entry)})
  end

  # The words alone give only 1,716 ids, so the suffix is always there. Without
  # it, every run past that number fails several inserts before one goes through.
  def generate_public_id do
    [
      random_word(@public_id_first_words),
      random_word(@public_id_middle_words),
      random_word(@public_id_last_words),
      random_suffix()
    ]
    |> Enum.join("-")
  end

  defp insert_with_public_id(attrs, attempts_remaining) do
    attrs = Map.put(attrs, :public_id, generate_public_id())

    case insert_execution(attrs) do
      {:error, changeset} ->
        if public_id_collision?(changeset) && attempts_remaining > 1,
          do: insert_with_public_id(attrs, attempts_remaining - 1),
          else: {:error, changeset}

      result ->
        result
    end
  end

  defp public_id_present?(attrs) do
    public_id = Map.get(attrs, :public_id) || Map.get(attrs, "public_id")
    is_binary(public_id) && public_id != ""
  end

  defp insert_execution(attrs) do
    %Execution{}
    |> Execution.changeset(attrs)
    |> Repo.insert()
  end

  defp public_id_collision?(%Ecto.Changeset{errors: errors}) do
    Enum.any?(errors, fn
      {:public_id, {_message, opts}} -> opts[:constraint] == :unique
      _error -> false
    end)
  end

  defp random_word(words) do
    Enum.at(words, :rand.uniform(length(words)) - 1)
  end

  defp random_suffix do
    1..4
    |> Enum.map(fn _index ->
      <<Enum.at(@public_id_suffix_alphabet, :rand.uniform(length(@public_id_suffix_alphabet)) - 1)>>
    end)
    |> Enum.join()
  end

  defp timestamp do
    DateTime.utc_now(:second)
  end

  defp execution_topic(execution_id), do: "executions:#{execution_id}"

  defp filter_by_workflow_id(query, opts) do
    case Map.get(opts, :workflow_id) || Map.get(opts, "workflow_id") do
      nil ->
        query

      workflow_id when is_integer(workflow_id) ->
        where(query, [e], e.flow_id == ^workflow_id)

      workflow_id when is_binary(workflow_id) ->
        case Integer.parse(workflow_id) do
          {id, ""} -> where(query, [e], e.flow_id == ^id)
          _ -> query
        end

      _ ->
        query
    end
  end

  defp filter_by_status(query, opts) do
    case Map.get(opts, :status) || Map.get(opts, "status") do
      status when is_binary(status) ->
        if status in Execution.statuses() do
          where(query, [e], e.status == ^status)
        else
          query
        end

      _ ->
        query
    end
  end

  defp filter_by_inserted_after(query, opts) do
    case parse_datetime(Map.get(opts, :inserted_after) || Map.get(opts, "inserted_after")) do
      {:ok, datetime} -> where(query, [e], e.inserted_at >= ^datetime)
      :error -> query
    end
  end

  defp filter_by_inserted_before(query, opts) do
    case parse_datetime(Map.get(opts, :inserted_before) || Map.get(opts, "inserted_before")) do
      {:ok, datetime} -> where(query, [e], e.inserted_at <= ^datetime)
      :error -> query
    end
  end

  defp parse_datetime(nil), do: :error

  defp parse_datetime(%DateTime{} = datetime), do: {:ok, datetime}

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      _ -> :error
    end
  end

  defp parse_datetime(_value), do: :error

  defp normalize_map(%{} = value), do: value
  defp normalize_map(value), do: %{"result" => value}

  defp normalize_error(%{} = error), do: error
  defp normalize_error(error) when is_binary(error), do: %{"message" => error}
  defp normalize_error(error), do: %{"message" => inspect(error)}
end
