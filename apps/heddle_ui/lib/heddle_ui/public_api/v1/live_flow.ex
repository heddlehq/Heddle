defmodule HeddleUI.PublicAPI.V1.LiveFlow do
  @moduledoc """
  Editing a flow with others from outside the browser, such as from Treadle: what the
  canvas does through `HeddleUI.FlowChannel`, over server-sent events to follow and
  plain requests to change, see `HeddleUI.PublicAPI.V1.LiveController`.

  The process that streams the events is a person on the flow like any canvas: it
  joins the flow's session (`HeddleCore.Flows.Session`) and is tracked in
  `HeddleUI.FlowPresence`, so the canvases show who is there from the terminal, and it
  sees them. The events, each with its JSON:

    * `ready`: `client`, `can_edit`, `user_id`, `seq`, `epoch` and `graph`. First, and
      again whenever the stream lost track of the changes: a client takes the graph
      as it comes.
    * `change`: `seq`, `epoch`, `ops`, `user_id`, `client`, `ref`, and the `graph` after
      it, so a client doesn't have to apply operations itself.
    * `presence`: `people`, everyone on the flow, with `client`, `kind`, `user_id`,
      `name`, `color`, and the nodes `selected` and the node `editing` of each.
    * `cursor`: `client`, `x` and `y` of a canvas pointer, on the canvas (nil when it
      left it), at most every `@cursor_every` ms.

  A graph has `nodes` (placed by `Heddle.Graph.Layout` when they have no position),
  `connections` and `comments`.
  """

  alias Heddle.Graph
  alias Heddle.Graph.Layout
  alias Heddle.Graph.Ops
  alias HeddleCore.Accounts.Scope
  alias HeddleCore.Flows
  alias HeddleCore.Flows.Session
  alias HeddleUI.FlowPresence

  @cursor_every 50
  @people_fields [:client, :kind, :user_id, :name, :color, :selected, :editing]

  defstruct [
    :scope,
    :flow_id,
    :client,
    :topic,
    :can_edit,
    :seq,
    :epoch,
    :graph,
    cursors: %{},
    cursor_timer: nil
  ]

  @doc """
  Joins the flow `id` for the calling process, which streams it. `can_write` says
  whether the caller's key may change flows at all. Returns `{:ok, state, events}` or
  `{:error, :not_found}`.
  """
  def start(%Scope{} = scope, id, opts \\ []) do
    with {:ok, flow} <- Flows.fetch_for(scope, :view, id) do
      # Before joining, so no change falls between what joining gives and what follows.
      :ok = Session.subscribe(flow.id)
      topic = FlowPresence.topic(flow.id)
      client = 9 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

      with {:ok, _flow, joined} <- Flows.join_session(scope, flow.id) do
        :ok = Phoenix.PubSub.subscribe(HeddleCore.PubSub, topic)
        :ok = Phoenix.PubSub.subscribe(HeddleCore.PubSub, focus_topic(flow.id, client))

        meta = scope.user |> FlowPresence.person() |> Map.put(:via, "api")
        {:ok, _ref} = FlowPresence.track(self(), topic, client, meta)

        state =
          %__MODULE__{
            scope: scope,
            flow_id: flow.id,
            client: client,
            topic: topic,
            can_edit: Keyword.get(opts, :can_write, true) and Flows.can?(scope, :edit, flow)
          }
          |> take(joined)

        {:ok, state, [ready(state), presence(state)]}
      else
        _error ->
          stop_following(flow.id, topic, client)
          {:error, :not_found}
      end
    end
  end

  @doc """
  Handles a message of the streaming process. Returns `{:ok, events, state}`, or
  `{:stop, events, state}` once the flow is gone for this person.
  """
  def handle({:flow_ops, %{flow_id: flow_id} = change}, %{flow_id: flow_id} = state) do
    cond do
      change.epoch == state.epoch and change.seq <= state.seq ->
        {:ok, [], state}

      change.epoch == state.epoch and change.seq == state.seq + 1 ->
        case Ops.apply(state.graph, change.ops) do
          {:ok, graph} ->
            state = %{state | graph: graph, seq: change.seq}
            {:ok, [change_event(change, state)], state}

          {:error, _reason} ->
            resync(state)
        end

      true ->
        resync(state)
    end
  end

  def handle(
        %Phoenix.Socket.Broadcast{topic: topic, event: "presence_diff"},
        %{topic: topic} = state
      ),
      do: {:ok, [presence(state)], state}

  def handle(
        %Phoenix.Socket.Broadcast{topic: topic, event: "cursor", payload: payload},
        %{topic: topic} = state
      ) do
    state = %{state | cursors: Map.put(state.cursors, payload.client, payload)}

    state =
      if state.cursor_timer,
        do: state,
        else: %{state | cursor_timer: Process.send_after(self(), :live_cursors, @cursor_every)}

    {:ok, [], state}
  end

  def handle(:live_cursors, state) do
    events =
      for {client, cursor} <- state.cursors,
          do: event("cursor", %{client: client, x: cursor[:x], y: cursor[:y]})

    {:ok, events, %{state | cursors: %{}, cursor_timer: nil}}
  end

  def handle({:live_focus, selected, editing}, state) do
    FlowPresence.update(self(), state.topic, state.client, fn meta ->
      %{meta | selected: selected, editing: editing}
    end)

    {:ok, [], state}
  end

  def handle(_message, state), do: {:ok, [], state}

  @doc "Leaves the flow, when the stream ends."
  def stop(%__MODULE__{} = state) do
    if state.cursor_timer, do: Process.cancel_timer(state.cursor_timer)
    stop_following(state.flow_id, state.topic, state.client)
    Session.leave(state.flow_id)
  end

  @doc """
  Points the stream `client` of the caller at nodes: the ones `selected` and the one
  `editing`, as a canvas does. Returns `:ok`, or `{:error, :not_found}` when the caller
  has no such stream on the flow.
  """
  def focus(%Scope{} = scope, id, client, params) when is_binary(client) do
    with {:ok, flow} <- Flows.fetch_for(scope, :view, id),
         %{metas: [%{via: "api", user_id: user_id} | _]} <-
           FlowPresence.get_by_key(FlowPresence.topic(flow.id), client),
         true <- scope.user != nil and user_id == scope.user.id do
      # Through PubSub, as the stream may be on another node of the cluster.
      Phoenix.PubSub.broadcast(
        HeddleCore.PubSub,
        focus_topic(flow.id, client),
        {:live_focus, selected(params), editing(params)}
      )
    else
      _none -> {:error, :not_found}
    end
  end

  def focus(_scope, _id, _client, _params), do: {:error, :not_found}

  @doc "Writes an event of the stream."
  def event(name, data), do: "event: #{name}\ndata: #{Jason.encode!(data)}\n\n"

  @doc "A comment line, which keeps proxies from closing a stream that is quiet a while."
  def keep_alive, do: ": keep-alive\n\n"

  @doc "A graph as the events and the API give it."
  def render_graph(graph) do
    %{
      nodes: Layout.place(graph.nodes, graph.connections),
      connections: Graph.normalize_connections(graph.connections),
      comments: graph.comments || []
    }
  end

  defp resync(state) do
    case Flows.join_session(state.scope, state.flow_id) do
      {:ok, _flow, joined} ->
        state = take(state, joined)
        {:ok, [ready(state)], state}

      _gone ->
        {:stop, [], state}
    end
  end

  defp take(state, %{graph: graph, seq: seq, epoch: epoch}),
    do: %{state | graph: Ops.normalize(graph), seq: seq, epoch: epoch}

  defp ready(state) do
    event("ready", %{
      client: state.client,
      can_edit: state.can_edit,
      user_id: state.scope.user && state.scope.user.id,
      seq: state.seq,
      epoch: state.epoch,
      graph: render_graph(state.graph)
    })
  end

  defp change_event(change, state) do
    event("change", %{
      seq: change.seq,
      epoch: change.epoch,
      ops: change.ops,
      user_id: change.user_id,
      client: change.client,
      ref: change.ref,
      graph: render_graph(state.graph)
    })
  end

  defp presence(state) do
    people =
      for {client, %{metas: [meta | _]}} <- FlowPresence.list(state.topic) do
        meta |> Map.put(:client, client) |> Map.take(@people_fields)
      end

    event("presence", %{people: people})
  end

  defp stop_following(flow_id, topic, client) do
    FlowPresence.untrack(self(), topic, client)
    Phoenix.PubSub.unsubscribe(HeddleCore.PubSub, topic)
    Phoenix.PubSub.unsubscribe(HeddleCore.PubSub, focus_topic(flow_id, client))
    Phoenix.PubSub.unsubscribe(HeddleCore.PubSub, Session.topic(flow_id))
  end

  defp focus_topic(flow_id, client), do: "live_flow:#{flow_id}:#{client}"

  defp selected(params) do
    params
    |> Map.get("selected", [])
    |> List.wrap()
    |> Enum.filter(&is_binary/1)
    |> Enum.take(200)
  end

  defp editing(params), do: if(is_binary(params["editing"]), do: params["editing"])
end
