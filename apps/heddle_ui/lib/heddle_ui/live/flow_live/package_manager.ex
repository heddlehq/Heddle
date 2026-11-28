defmodule HeddleUI.FlowLive.PackageManager do
  @moduledoc """
  What a package's node shows in its drawer, besides its fields: a panel of what it
  keeps while its flow runs (see `c:Bobbin.Node.panel/2`), like an agent's instances,
  and the link of a trigger people talk to (see `HeddleCore.Chats`).
  """

  use Gettext, backend: HeddleUI.Gettext
  use Phoenix.VerifiedRoutes, endpoint: HeddleUI.Endpoint, router: HeddleUI.Router

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]

  require Logger

  alias Heddle.Graph
  alias HeddleCore.{Chats, Flows}
  alias HeddleCore.Flows.Versions

  def initial_assigns, do: [package_panel: nil, chat_link: nil]

  @doc "Reads the panel and the chat link when the drawer opens on a node."
  def opened(socket, %{"type" => type, "id" => node_id} = node_data) do
    module = HeddleNodes.Packages.get_node_module(type)

    socket
    |> assign(:package_panel, panel(socket, module, node_data))
    |> assign(:chat_link, chat_link(socket, type, node_id))
  end

  def opened(socket, _node_data), do: assign(socket, :package_panel, nil) |> assign(:chat_link, nil)

  @doc "Reads the panel again, for its Refresh button."
  def refresh(socket) do
    case socket.assigns[:editing_node_data] do
      %{"type" => type} = node_data ->
        assign(socket, :package_panel, panel(socket, HeddleNodes.Packages.get_node_module(type), node_data))

      _none ->
        socket
    end
  end

  defp panel(socket, module, node_data) do
    if module && Code.ensure_loaded?(module) && function_exported?(module, :panel, 2) do
      try do
        module.panel(socket.assigns.current_flow.workspace_id, controls(node_data))
      rescue
        error ->
          Logger.warning("The panel of #{node_data["type"]} failed: #{Exception.message(error)}")
          [%{title: gettext("Panel"), text: gettext("This panel couldn't be read now.")}]
      end
    end
  end

  # The drawer holds each control as `%{"value" => ...}`.
  defp controls(%{"controls" => controls}) when is_map(controls) do
    Map.new(controls, fn
      {key, %{"value" => value}} -> {key, value}
      {key, value} -> {key, value}
    end)
  end

  defp controls(_node_data), do: %{}

  defp chat_link(socket, type, node_id) do
    %{current_scope: scope, current_flow: flow} = socket.assigns

    with module when not is_nil(module) <- HeddleUI.ChatLive.Show.chat_module(type),
         %{} = flow <- Flows.get_flow(scope, flow.id),
         {:ok, chat} <- Chats.link(scope, flow, node_id) do
      %{
        node_id: node_id,
        url: HeddleUI.Endpoint.url() <> ~p"/c/#{chat.token}",
        test_url: ~p"/flows/#{flow.id}/chat/#{node_id}",
        published: published?(flow, node_id, type)
      }
    else
      _other -> nil
    end
  end

  defp published?(flow, node_id, type) do
    case Versions.published_flow(flow) do
      nil -> false
      published -> match?(%Graph.Node{type: ^type}, published |> Graph.new() |> Graph.get(node_id))
    end
  end

  @doc "Gives the chat a new link, so the old one stops working."
  def regenerate_chat(socket) do
    %{current_scope: scope, current_flow: flow, chat_link: link} = socket.assigns

    case link && Chats.regenerate(scope, flow, link.node_id) do
      {:ok, _chat} ->
        type = socket.assigns.editing_node_data["type"]

        socket
        |> assign(:chat_link, chat_link(socket, type, link.node_id))
        |> put_flash(:info, gettext("The chat has a new link. The old one no longer works."))

      _other ->
        put_flash(socket, :error, gettext("Your role in this workspace can't change this chat."))
    end
  end
end
