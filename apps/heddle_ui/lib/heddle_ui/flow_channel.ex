defmodule HeddleUI.FlowChannel do
  @moduledoc """
  A canvas editing a flow, on `"canvas:<id>"`. Joining gives the draft as the session of
  the flow has it (see `HeddleCore.Flows.Session`), and after that every change anyone
  makes, in order, and who else is there (see `HeddleUI.FlowPresence`).

  In: `"ops"` with `ops`, `ref` and `client`, answered with the number of the change or
  a reason it was refused; `"snapshot"`, answered with the draft, for a canvas that lost
  track; `"cursor"` with `x` and `y` on the canvas (or nil, when it left it), `"drag"`
  with the `positions` of what is being dragged, and `"focus"` with the nodes
  `selected` and the node `editing` in the drawer.

  Out: `"ops"`, each change as the session tells it; `"cursor"` and `"drag"` of the
  others, with their `client`; and `presence_state` and `presence_diff`.

  Someone who may only see the flow follows it, and others see them, but they can't
  change it or drag anything.
  """

  use Phoenix.Channel

  alias Heddle.Graph
  alias Heddle.Graph.Layout
  alias HeddleCore.Flows
  alias HeddleCore.Flows.Session
  alias HeddleUI.AIChat
  alias HeddleUI.FlowPresence

  @impl true
  def join("canvas:" <> id, _params, socket) do
    scope = socket.assigns.current_scope

    with {:ok, flow, joined} <- Flows.join_session(scope, id) do
      :ok = Session.subscribe(flow.id)
      client = 9 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
      can_edit = Flows.can?(scope, :edit, flow)

      socket = assign(socket, flow_id: flow.id, client: client, can_edit: can_edit)
      send(self(), :after_join)

      user_id = scope.user && scope.user.id

      {:ok, reply(joined) |> Map.merge(%{client: client, can_edit: can_edit, user_id: user_id}),
       socket}
    else
      _error -> {:error, %{reason: "not_found"}}
    end
  end

  @impl true
  def handle_in("ops", %{"ops" => ops} = params, socket) do
    meta = %{client: socket.assigns.client, ref: params["ref"]}

    case Flows.apply_operations(socket.assigns.current_scope, socket.assigns.flow_id, ops, meta) do
      {:ok, seq} -> {:reply, {:ok, %{seq: seq}}, socket}
      {:error, :forbidden} -> {:reply, {:error, %{reason: "forbidden"}}, socket}
      {:error, reason} when is_binary(reason) -> {:reply, {:error, %{reason: reason}}, socket}
      {:error, _reason} -> {:reply, {:error, %{reason: "refused"}}, socket}
    end
  end

  def handle_in("cursor", %{"x" => x, "y" => y}, socket) when is_number(x) and is_number(y) do
    broadcast_from(socket, "cursor", %{client: socket.assigns.client, x: x, y: y})
    {:noreply, socket}
  end

  def handle_in("cursor", _params, socket) do
    broadcast_from(socket, "cursor", %{client: socket.assigns.client, x: nil, y: nil})
    {:noreply, socket}
  end

  # How what is being dragged moves, before it is dropped and becomes a change.
  def handle_in("drag", %{"positions" => positions}, %{assigns: %{can_edit: true}} = socket)
      when is_map(positions) and map_size(positions) <= 200 do
    broadcast_from(socket, "drag", %{client: socket.assigns.client, positions: positions})
    {:noreply, socket}
  end

  def handle_in("drag", _params, socket), do: {:noreply, socket}

  def handle_in("focus", params, socket) do
    selected =
      params
      |> Map.get("selected", [])
      |> List.wrap()
      |> Enum.filter(&is_binary/1)
      |> Enum.take(200)

    editing = if is_binary(params["editing"]), do: params["editing"]

    FlowPresence.update(self(), socket.topic, socket.assigns.client, fn meta ->
      %{meta | selected: selected, editing: editing}
    end)

    {:noreply, socket}
  end

  def handle_in("snapshot", _params, socket) do
    case Flows.join_session(socket.assigns.current_scope, socket.assigns.flow_id) do
      {:ok, _flow, joined} -> {:reply, {:ok, reply(joined)}, socket}
      _error -> {:reply, {:error, %{reason: "not_found"}}, socket}
    end
  end

  @impl true
  def handle_info(:after_join, socket) do
    {:ok, _ref} =
      FlowPresence.track(
        self(),
        socket.topic,
        socket.assigns.client,
        FlowPresence.person(socket.assigns.current_scope.user)
      )

    push(socket, "presence_state", FlowPresence.list(socket.topic))
    {:noreply, socket}
  end

  def handle_info({:flow_ops, change}, socket) do
    push(socket, "ops", Map.take(change, [:epoch, :seq, :ops, :user_id, :client, :ref]))
    {:noreply, socket}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  # A node saved without a position is placed, see `Heddle.Graph.Layout`.
  defp reply(%{graph: graph, seq: seq, epoch: epoch}) do
    %{
      graph: %{
        nodes: Layout.place(graph.nodes, graph.connections),
        connections: Graph.normalize_connections(graph.connections),
        comments: graph.comments
      },
      seq: seq,
      epoch: epoch,
      definitions: AIChat.node_definitions()
    }
  end
end
