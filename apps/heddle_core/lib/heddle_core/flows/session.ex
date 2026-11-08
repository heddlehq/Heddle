defmodule HeddleCore.Flows.Session do
  @moduledoc """
  The one process that changes the draft of a flow while people edit it.

  Everyone who edits a flow sends their changes here as operations (see
  `Heddle.Graph.Ops`). The session applies them one at a time, in the order they
  arrive, checks the graph is still one, and tells everyone what changed, numbered in
  order. That order is what settles two people changing the same thing: the last one
  to arrive wins. An operation that doesn't apply goes back to who sent it, and nobody
  else ever sees it.

  There is one per flow in the whole cluster, through `Horde.Registry`. It saves the
  draft `@flush_after` ms after the last change, when it stops and when asked to
  (before a run or a publish), and stops some time after the last person leaves.
  Writing a whole flow at once, as the API and the agents do, goes through it too, so
  the database has one writer: see `HeddleCore.Flows.update_flow/3`.

  Subscribers of `topic/1` receive `{:flow_ops, change}`, with `epoch` (which changes
  when a session starts again, so whoever was following reloads), `seq`, `ops`,
  `user_id` and the `client` and `ref` the sender gave.
  """

  use GenServer, restart: :temporary

  require Logger

  alias Heddle.Graph.Layout
  alias Heddle.Graph.Ops
  alias HeddleCore.Flows
  alias HeddleCore.Flows.{Flow, GraphValidator, Versions}
  alias HeddleCore.Repo

  @registry HeddleCore.Flows.SessionRegistry
  @supervisor HeddleCore.Flows.SessionSupervisor
  @idle_after to_timeout(second: 30)

  def registry, do: @registry
  def supervisor, do: @supervisor

  @doc "Where the changes of a flow are told."
  def topic(flow_id), do: "flow:#{flow_id}:ops"

  def subscribe(flow_id), do: Phoenix.PubSub.subscribe(HeddleCore.PubSub, topic(flow_id))

  def start_link(flow_id) do
    GenServer.start_link(__MODULE__, flow_id, name: via(flow_id))
  end

  def child_spec(flow_id) do
    %{id: {__MODULE__, flow_id}, start: {__MODULE__, :start_link, [flow_id]}, restart: :temporary}
  end

  ## API

  @doc """
  Joins the session of a flow, starting it if needed, until the caller leaves or
  exits. Returns `{:ok, %{graph: graph, seq: seq, epoch: epoch}}`.
  """
  def join(flow_id, user_id \\ nil), do: call(flow_id, {:join, user_id})

  def leave(flow_id), do: cast_if_running(flow_id, {:leave, self()})

  @doc """
  Applies operations from `user_id`. Returns `{:ok, seq}`, or `{:error, reason}` and
  nothing changes. `meta` may say the `client` and `ref` that sent them.
  """
  def apply_ops(flow_id, user_id, ops, meta \\ %{}),
    do: call(flow_id, {:apply, user_id, ops, meta})

  @doc """
  Makes the draft `graph` (any of `:nodes`, `:connections` and `:comments`), as
  operations everyone sees, and saves it at once. Returns `{:ok, flow}`.
  """
  def replace(flow_id, user_id, graph, opts \\ []),
    do: call(flow_id, {:replace, user_id, graph, opts})

  @doc "Saves what the session has, if there is one. Returns `:ok`."
  def flush(flow_id) do
    case whereis(flow_id) do
      nil -> :ok
      pid -> safe_call(pid, :flush)
    end
  end

  @doc "The draft as the session has it, or nil when no one edits the flow."
  def peek(flow_id) do
    case whereis(flow_id) do
      nil ->
        nil

      pid ->
        case safe_call(pid, :peek) do
          {:ok, graph} -> graph
          _other -> nil
        end
    end
  end

  def whereis(flow_id) do
    case Horde.Registry.lookup(@registry, flow_id) do
      [{pid, _value}] -> pid
      [] -> nil
    end
  end

  defp via(flow_id), do: {:via, Horde.Registry, {@registry, flow_id}}

  defp call(flow_id, message, attempts \\ 2) do
    with {:ok, pid} <- ensure_started(flow_id) do
      case safe_call(pid, message) do
        {:error, :gone} when attempts > 1 -> call(flow_id, message, attempts - 1)
        result -> result
      end
    end
  end

  defp ensure_started(flow_id) do
    case Horde.DynamicSupervisor.start_child(@supervisor, child_spec(flow_id)) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      :ignore -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp safe_call(pid, message) do
    GenServer.call(pid, {message, self()}, to_timeout(second: 15))
  catch
    :exit, {reason, _call} when reason in [:noproc, :normal, :shutdown] -> {:error, :gone}
    :exit, {{:shutdown, _}, _call} -> {:error, :gone}
  end

  defp cast_if_running(flow_id, message) do
    case whereis(flow_id) do
      nil -> :ok
      pid -> GenServer.cast(pid, message)
    end
  end

  ## Server

  @impl true
  def init(flow_id) do
    Process.flag(:trap_exit, true)

    {:ok,
     %{
       flow_id: flow_id,
       epoch: epoch(),
       seq: 0,
       graph: nil,
       dirty?: false,
       edited?: false,
       contributors: [],
       last_author: nil,
       flush_timer: nil,
       participants: %{},
       idle_timer: nil
     }, {:continue, :idle}}
  end

  @impl true
  def handle_continue(:idle, state), do: {:noreply, schedule_idle(state)}

  @impl true
  def handle_call({message, caller}, _from, state) do
    allow_sandbox(caller)

    case load(state) do
      {:ok, state} ->
        {reply, state} = handle(message, caller, state)
        {:reply, reply, state}

      {:error, reason} ->
        {:stop, :normal, {:error, reason}, state}
    end
  end

  defp handle({:join, user_id}, caller, state) do
    ref = Process.monitor(caller)
    participants = Map.put(state.participants, caller, %{ref: ref, user_id: user_id})
    state = %{state | participants: participants} |> cancel_idle()

    {{:ok, %{graph: state.graph, seq: state.seq, epoch: state.epoch}}, state}
  end

  defp handle({:apply, user_id, ops, meta}, _caller, state) do
    case change(state, ops) do
      {:ok, graph} ->
        state
        |> commit(graph, ops, user_id, meta)
        |> then(&{{:ok, &1.seq}, &1})

      {:error, reason} ->
        {{:error, reason}, state}
    end
  end

  defp handle({:replace, user_id, graph, opts}, _caller, state) do
    new = state.graph |> Map.merge(given(graph)) |> Ops.normalize() |> place_new(state.graph)
    ops = Ops.between(state.graph, new)

    case change(state, ops) do
      {:ok, graph} ->
        # It saves right after, so it doesn't schedule saving.
        state =
          if ops == [],
            do: state,
            else:
              commit(
                state,
                graph,
                ops,
                user_id,
                %{client: Keyword.get(opts, :client, "server")},
                false
              )

        case save(state, Keyword.get(opts, :checkpoint, true)) do
          {:ok, nil, state} -> {{:ok, Repo.get(Flow, state.flow_id)}, state}
          {:ok, flow, state} -> {{:ok, flow}, state}
          {:error, reason, state} -> {{:error, reason}, state}
        end

      {:error, reason} ->
        {{:error, reason}, state}
    end
  end

  defp handle(:flush, _caller, state) do
    case save(state, true) do
      {:ok, _flow, state} -> {:ok, state}
      {:error, _reason, state} -> {:ok, state}
    end
  end

  defp handle(:peek, _caller, state), do: {{:ok, state.graph}, state}

  @impl true
  def handle_cast({:leave, pid}, state), do: {:noreply, drop(state, pid)}

  @impl true
  def handle_info(:flush, state) do
    {_result, _flow, state} = save(%{state | flush_timer: nil}, true)
    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state), do: {:noreply, drop(state, pid)}

  def handle_info(:idle, %{participants: participants} = state)
      when map_size(participants) == 0 do
    {:stop, :normal, state}
  end

  def handle_info(:idle, state), do: {:noreply, %{state | idle_timer: nil}}

  def handle_info({:EXIT, _pid, reason}, state), do: {:stop, reason, state}

  def handle_info(_message, state), do: {:noreply, state}

  # Saves on the way out, and keeps what the people who edited it left.
  @impl true
  def terminate(_reason, %{graph: graph, edited?: true} = state) when not is_nil(graph) do
    {_result, _flow, _state} = save(state, false)

    case Repo.get(Flow, state.flow_id) do
      nil -> :ok
      flow -> Versions.checkpoint(flow, state.last_author, flush: false)
    end

    :ok
  rescue
    error ->
      # A test that is over takes its database with it.
      level = if Application.get_env(:heddle_core, :sandbox_sessions), do: :debug, else: :warning
      Logger.log(level, "A flow session didn't save as it stopped: #{Exception.message(error)}")
  end

  def terminate(_reason, _state), do: :ok

  ## Helpers

  defp load(%{graph: nil} = state) do
    case Repo.get(Flow, state.flow_id) do
      nil -> {:error, :not_found}
      flow -> {:ok, %{state | graph: Ops.normalize(flow)}}
    end
  end

  defp load(state), do: {:ok, state}

  defp change(state, ops) do
    with {:ok, graph} <- Ops.apply(state.graph, ops),
         :ok <- validate(graph) do
      {:ok, graph}
    end
  end

  defp validate(graph) do
    with :ok <- GraphValidator.validate(graph.nodes, graph.connections, draft: true),
         :ok <- GraphValidator.validate_comments(graph.comments) do
      :ok
    else
      {:error, field, message} -> {:error, "#{field} #{message}"}
    end
  end

  defp commit(state, graph, ops, user_id, meta, schedule? \\ true) do
    seq = state.seq + 1

    Phoenix.PubSub.broadcast(
      HeddleCore.PubSub,
      topic(state.flow_id),
      {:flow_ops,
       %{
         flow_id: state.flow_id,
         epoch: state.epoch,
         seq: seq,
         ops: ops,
         user_id: user_id,
         client: meta[:client] || meta["client"],
         ref: meta[:ref] || meta["ref"]
       }}
    )

    contributors =
      if user_id && user_id not in state.contributors,
        do: state.contributors ++ [user_id],
        else: state.contributors

    %{
      state
      | graph: graph,
        seq: seq,
        dirty?: true,
        edited?: true,
        contributors: contributors,
        last_author: user_id || state.last_author
    }
    |> then(&if(schedule?, do: schedule_flush(&1), else: &1))
  end

  defp save(%{dirty?: false} = state, _checkpoint?), do: {:ok, nil, state}

  defp save(state, checkpoint?) do
    state = cancel_flush(state)

    with %Flow{} = flow <- Repo.get(Flow, state.flow_id) || {:error, :not_found},
         contributors = Enum.uniq((flow.draft_contributor_ids || []) ++ state.contributors),
         {:ok, flow} <-
           flow |> Flow.draft_changeset(graph_attrs(state.graph), contributors) |> Repo.update() do
      Flows.broadcast_flow_updated(flow)

      if checkpoint?,
        do: Versions.checkpoint_if_due(flow, state.last_author, DateTime.utc_now(), flush: false)

      {:ok, flow, %{state | dirty?: false, contributors: []}}
    else
      {:error, reason} ->
        Logger.warning("A flow session couldn't save flow #{state.flow_id}: #{inspect(reason)}")
        {:error, reason, state}
    end
  end

  defp graph_attrs(graph),
    do: %{nodes: graph.nodes, connections: graph.connections, comments: graph.comments}

  # A node written without a position goes where `Heddle.Graph.Layout` puts it, for
  # every canvas to draw it there.
  defp place_new(new, old) do
    known = MapSet.new(old.nodes, & &1["id"])
    placed = new.nodes |> Layout.place(new.connections) |> Map.new(&{&1["id"], &1["position"]})

    nodes =
      Enum.map(new.nodes, fn node ->
        if is_nil(node["position"]) and not MapSet.member?(known, node["id"]),
          do: Map.put(node, "position", placed[node["id"]]),
          else: node
      end)

    %{new | nodes: nodes}
  end

  # What a writer sent of the graph, by atom: what it leaves out stays as it is.
  defp given(graph) do
    for {key, value} <- graph, key = to_key(key), key != nil, into: %{}, do: {key, value || []}
  end

  defp to_key(key) when is_atom(key), do: key
  defp to_key("nodes"), do: :nodes
  defp to_key("connections"), do: :connections
  defp to_key("comments"), do: :comments
  defp to_key(_key), do: nil

  defp schedule_flush(%{flush_timer: nil} = state) do
    case flush_after() do
      :sync ->
        {_result, _flow, state} = save(state, true)
        state

      ms ->
        %{state | flush_timer: Process.send_after(self(), :flush, ms)}
    end
  end

  defp schedule_flush(state), do: state

  defp cancel_flush(%{flush_timer: nil} = state), do: state

  defp cancel_flush(%{flush_timer: timer} = state) do
    Process.cancel_timer(timer)
    %{state | flush_timer: nil}
  end

  defp drop(state, pid) do
    case Map.pop(state.participants, pid) do
      {nil, _participants} ->
        state

      {%{ref: ref}, participants} ->
        Process.demonitor(ref, [:flush])
        schedule_idle(%{state | participants: participants})
    end
  end

  defp schedule_idle(%{participants: participants, idle_timer: nil} = state)
       when map_size(participants) == 0 do
    %{state | idle_timer: Process.send_after(self(), :idle, idle_after())}
  end

  defp schedule_idle(state), do: state

  defp cancel_idle(%{idle_timer: nil} = state), do: state

  defp cancel_idle(%{idle_timer: timer} = state) do
    Process.cancel_timer(timer)
    %{state | idle_timer: nil}
  end

  defp epoch, do: 6 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

  defp flush_after, do: Application.get_env(:heddle_core, :session_flush_after, 1_000)
  defp idle_after, do: Application.get_env(:heddle_core, :session_idle_after, @idle_after)

  # In tests, the database belongs to the test, and the session works for it.
  # A LiveView or a channel reaches it through the processes that started them.
  defp allow_sandbox(caller) do
    if Application.get_env(:heddle_core, :sandbox_sessions, false) do
      callers =
        case Process.info(caller, :dictionary) do
          {:dictionary, dictionary} -> Keyword.get(dictionary, :"$callers", [])
          nil -> []
        end

      Enum.find([caller | callers], fn pid ->
        try do
          Ecto.Adapters.SQL.Sandbox.allow(Repo, pid, self()) != :not_found
        rescue
          _error -> false
        end
      end)
    end
  end
end
