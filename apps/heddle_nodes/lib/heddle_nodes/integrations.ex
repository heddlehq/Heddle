defmodule HeddleNodes.Integrations do
  @moduledoc """
  The integrations a workspace can install: the services whose actions are nodes.

  The other nodes (triggers, logic, data, HTTP, AI, Spool) are the core and are always
  available. A node of an integration shows in the editor only once its workspace has
  installed it, so the sidebar holds what the workspace uses and not every service.

  An integration is the set of actions of one service, by its group when its category
  holds several services (the databases), or by its category.
  """

  alias HeddleNodes.Nodes

  @type t :: %{
          id: String.t(),
          title: String.t(),
          category: atom(),
          icon: String.t(),
          color: String.t(),
          nodes: [map()],
          community: boolean(),
          version: String.t() | nil
        }

  # Spool is Heddle's own table store, so it needs no service and stays in the core.
  @core_groups ["Spool"]

  @doc "Every integration, in the order the sidebar shows them."
  @spec all() :: [t()]
  def all do
    Nodes.visible_nodes()
    |> Enum.filter(&integration_node?/1)
    |> Enum.group_by(&id_for/1)
    |> Enum.map(fn {id, [first | _] = nodes} ->
      %{
        id: id,
        title: title(first),
        category: first.category,
        icon: first.icon,
        color: first.color,
        nodes: nodes,
        community: first[:community] != nil,
        version: first[:version]
      }
    end)
    |> Enum.sort_by(&String.downcase(&1.title))
  end

  @doc "The integration with `id`, or nil."
  @spec get(String.t()) :: t() | nil
  def get(id), do: Enum.find(all(), &(&1.id == id))

  @doc "The id of the integration `node` belongs to, or nil for a node of the core."
  @spec integration_of(map() | String.t()) :: String.t() | nil
  def integration_of(name) when is_binary(name) do
    case Nodes.get_node(name) do
      nil -> nil
      node -> integration_of(node)
    end
  end

  def integration_of(node) do
    if integration_node?(node), do: id_for(node)
  end

  @doc "Whether `node` belongs to the core, which every workspace has."
  @spec core?(map()) :: boolean()
  def core?(node), do: not integration_node?(node)

  @doc """
  The integrations a workspace has: the ones it installed and the ones its flows
  already use, so a flow never shows a node its workspace doesn't have.
  """
  @spec installed_ids(Enumerable.t(), Enumerable.t()) :: MapSet.t(String.t())
  def installed_ids(installed, used_node_types) do
    used = used_node_types |> Enum.map(&integration_of/1) |> Enum.reject(&is_nil/1)
    MapSet.new(Enum.concat(installed, used))
  end

  @doc "Whether `node` shows for a workspace with the `installed` integrations."
  @spec available?(map(), MapSet.t(String.t())) :: boolean()
  def available?(node, installed) do
    case integration_of(node) do
      nil -> true
      id -> MapSet.member?(installed, id)
    end
  end

  @doc "The names of the nodes of the integration with `id`."
  @spec node_names(String.t()) :: [String.t()]
  def node_names(id) do
    case get(id) do
      nil -> []
      integration -> Enum.map(integration.nodes, & &1.name)
    end
  end

  defp title(%{community: id} = node) when is_binary(id),
    do: node.name |> String.split(": ", parts: 2) |> hd()

  defp title(%{integration: id} = node) when is_binary(id),
    do: node.name |> String.split(": ", parts: 2) |> hd()

  defp title(node), do: node[:group] || Nodes.category_label(node.category)

  defp integration_node?(%{community: id}) when is_binary(id), do: true
  defp integration_node?(%{integration: id}) when is_binary(id), do: true

  defp integration_node?(node) do
    node.category in Nodes.service_categories() and node[:group] not in @core_groups
  end

  defp id_for(%{community: id}) when is_binary(id), do: id
  defp id_for(%{integration: id}) when is_binary(id), do: id

  defp id_for(node) do
    (node[:group] || to_string(node.category))
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "_")
  end
end
