defmodule HeddleUI.FlowLive.NodePaletteManager do
  @moduledoc """
  Socket reducers and helper functions for node sidebar, search, categorization,
  and quick-add modal in `FlowLive.Editor`.
  """

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [push_event: 3]

  @max_recent_nodes 5

  @doc """
  Returns the default socket assigns for node search, categories, and creation modals.
  """
  # `installed` holds the ids of the integrations the workspace has, see
  # `HeddleUI.Integrations`. Only their nodes show, next to the core.
  def initial_assigns(installed \\ :all) do
    [
      installed_integrations: installed,
      nodes_by_category: nodes_by_category("", installed),
      uninstalled_integrations: [],
      node_search_query: "",
      collapsed_node_categories: MapSet.new(),
      recent_nodes: [],
      available_nodes: filter_nodes("", installed),
      filtered_nodes: filter_nodes("", installed),
      node_modal_search_query: "",
      create_node_modal_open: false,
      selected_position: nil
    ]
  end

  @doc """
  Filters nodes in the sidebar by category and search query.
  """
  def filter_sidebar_nodes(socket, query) do
    installed = socket.assigns.installed_integrations

    assign(socket,
      node_search_query: query,
      nodes_by_category: nodes_by_category(query, installed),
      uninstalled_integrations: uninstalled_integrations(query, installed)
    )
  end

  @doc """
  Shows the nodes of the integration `id` once the workspace installed it.
  """
  def integration_installed(socket, id) do
    installed =
      case socket.assigns.installed_integrations do
        :all -> :all
        ids -> MapSet.put(ids, id)
      end

    socket
    |> assign(installed_integrations: installed)
    |> filter_sidebar_nodes(socket.assigns.node_search_query)
    |> assign(
      filtered_nodes: filter_nodes("", installed),
      available_nodes: filter_nodes("", installed)
    )
  end

  @doc """
  Filters nodes displayed in the quick creation modal.
  """
  def filter_modal_nodes(socket, query) do
    assign(socket,
      filtered_nodes: filter_nodes(query, socket.assigns.installed_integrations),
      node_modal_search_query: query
    )
  end

  @doc """
  Toggles collapse/expanded state of a category in the sidebar.
  """
  def toggle_category(socket, category_param) do
    case category_from_param(category_param) do
      nil ->
        socket

      category ->
        collapsed = socket.assigns.collapsed_node_categories

        collapsed =
          if MapSet.member?(collapsed, category) do
            MapSet.delete(collapsed, category)
          else
            MapSet.put(collapsed, category)
          end

        assign(socket, collapsed_node_categories: collapsed)
    end
  end

  @doc """
  Opens the node creation modal at a specific canvas (x, y) coordinate.
  """
  def open_create_modal(socket, %{"x" => x, "y" => y}) do
    assign(socket,
      create_node_modal_open: true,
      selected_position: %{"x" => x, "y" => y}
    )
  end

  @doc """
  Closes the node creation modal.
  """
  def close_create_modal(socket) do
    assign(socket,
      create_node_modal_open: false,
      selected_position: nil,
      filtered_nodes: filter_nodes("", socket.assigns.installed_integrations),
      node_modal_search_query: ""
    )
  end

  @doc """
  Creates a node selected from the quick modal and pushes `add_node` to the canvas.
  """
  def create_node_from_modal(socket, name) do
    position = socket.assigns.selected_position || %{"x" => 100, "y" => 100}

    node_data = %{
      "id" => "node_#{:os.system_time(:millisecond)}_#{:rand.uniform(1000)}",
      "label" => name,
      "position" => position
    }

    socket
    |> assign(
      create_node_modal_open: false,
      selected_position: nil,
      filtered_nodes: filter_nodes("", socket.assigns.installed_integrations),
      node_modal_search_query: ""
    )
    |> record_recent_node(name)
    |> push_event("add_node", %{
      name: name,
      definition: HeddleNodes.Nodes.get_node(name),
      data: node_data
    })
  end

  @doc """
  Adds a node directly by name and pushes `add_node` to the canvas.
  """
  def add_node(socket, name) do
    definition = HeddleNodes.Nodes.get_node(name)

    socket
    |> record_recent_node(name)
    |> push_event("add_node", %{name: name, definition: definition})
  end

  @doc """
  Records a node as recently used.
  """
  def record_recent_node(socket, name) do
    case HeddleNodes.Nodes.get_node(name) do
      nil ->
        socket

      node ->
        recent_nodes =
          socket.assigns.recent_nodes
          |> Enum.reject(&(&1.name == name))
          |> then(&[node | &1])
          |> Enum.take(@max_recent_nodes)

        assign(socket, recent_nodes: recent_nodes)
    end
  end

  @doc """
  Forgets the recently used nodes.
  """
  def clear_recent_nodes(socket), do: assign(socket, recent_nodes: [])

  @doc """
  Filters the visible nodes the workspace has that match a query string.
  """
  def filter_nodes(query, installed \\ :all) do
    HeddleNodes.Nodes.visible_nodes()
    |> Enum.filter(&available?(&1, installed))
    |> Enum.filter(&matches?(&1, query))
  end

  @doc """
  The integrations the workspace hasn't installed that have a node matching a query,
  so a search can offer them. None without a query.
  """
  def uninstalled_integrations(_query, :all), do: []

  def uninstalled_integrations(query, installed) do
    if String.trim(query || "") == "" do
      []
    else
      Enum.filter(HeddleNodes.Integrations.all(), fn integration ->
        not MapSet.member?(installed, integration.id) and
          (matches?(%{name: integration.title, category: integration.category}, query) or
             Enum.any?(integration.nodes, &matches?(&1, query)))
      end)
    end
  end

  defp available?(_node, :all), do: true
  defp available?(node, installed), do: HeddleNodes.Integrations.available?(node, installed)

  defp matches?(node, query) do
    case String.trim(query || "") do
      "" ->
        true

      query ->
        query = String.downcase(query)

        Enum.any?(
          [node.name, to_string(node.category), Map.get(node, :description, "")],
          &String.contains?(String.downcase(&1), query)
        )
    end
  end

  @doc """
  Returns the nodes the workspace has, grouped by category and sorted.
  """
  def nodes_by_category(query, installed \\ :all) do
    query
    |> filter_nodes(installed)
    |> Enum.group_by(& &1.category)
    |> Enum.sort_by(fn {category, _nodes} -> category_sort_index(category) end)
  end

  defp category_sort_index(:trigger), do: 0
  defp category_sort_index(:flow_control), do: 1
  defp category_sort_index(:data_manipulation), do: 2
  defp category_sort_index(:code), do: 3
  defp category_sort_index(:ai), do: 4
  defp category_sort_index(:http), do: 5
  defp category_sort_index(:utility), do: 20

  defp category_sort_index(category) do
    case Enum.find_index(HeddleNodes.Nodes.service_categories(), &(&1 == category)) do
      nil -> 21
      position -> 6 + position
    end
  end

  @doc """
  Finds matching category atom from string param.
  """
  def category_from_param(category) do
    HeddleNodes.Nodes.visible_nodes()
    |> Enum.map(& &1.category)
    |> Enum.uniq()
    |> Enum.find(&(to_string(&1) == category))
  end
end
