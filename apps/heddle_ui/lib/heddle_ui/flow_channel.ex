defmodule HeddleUI.FlowChannel do
  @moduledoc """
  A canvas editing a flow. Joining gives the draft as the session of the flow has it
  (see `HeddleCore.Flows.Session`), and after that every change anyone makes, in order.

  In: `"ops"` with `ops`, `ref` and `client`, answered with the number of the change or
  a reason it was refused; `"snapshot"`, answered with the draft, for a canvas that lost
  track. Out: `"ops"`, each change as the session tells it.

  Someone who may only see the flow follows it and can't change it.
  """

  use Phoenix.Channel

  alias Heddle.Graph
  alias Heddle.Graph.Layout
  alias HeddleCore.Flows
  alias HeddleCore.Flows.Session
  alias HeddleUI.AIChat

  @impl true
  def join("flow:" <> id, _params, socket) do
    scope = socket.assigns.current_scope

    with {:ok, flow, joined} <- Flows.join_session(scope, id) do
      :ok = Session.subscribe(flow.id)
      client = 9 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
      can_edit = Flows.can?(scope, :edit, flow)

      socket = assign(socket, flow_id: flow.id, client: client, can_edit: can_edit)

      {:ok, reply(joined) |> Map.merge(%{client: client, can_edit: can_edit}), socket}
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

  def handle_in("snapshot", _params, socket) do
    case Flows.join_session(socket.assigns.current_scope, socket.assigns.flow_id) do
      {:ok, _flow, joined} -> {:reply, {:ok, reply(joined)}, socket}
      _error -> {:reply, {:error, %{reason: "not_found"}}, socket}
    end
  end

  @impl true
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
