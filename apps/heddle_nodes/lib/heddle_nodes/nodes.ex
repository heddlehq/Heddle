defmodule HeddleNodes.Nodes do
  @moduledoc """
  Central registry for all node definitions.
  """

  def all_nodes do
    HeddleNodes.get_definitions()
  end

  def get_node(name) do
    Enum.find(all_nodes(), fn node -> node.name == name end)
  end

  def get_node_module(name) do
    HeddleNodes.get_node_module(name)
  end

  def nodes_by_category do
    all_nodes()
    |> Enum.filter(fn node -> Map.get(node, :show, true) end)
    |> Enum.group_by(& &1.category)
  end

  def visible_nodes do
    all_nodes()
    |> Enum.filter(fn node -> Map.get(node, :show, true) end)
  end

  @doc """
  The categories that hold the actions of a service.
  """
  def service_categories, do: [:database, :email, :ftp, :google_sheets, :s3, :slack]

  def category_label(:ai), do: "AI"
  def category_label(:ftp), do: "FTP"
  def category_label(:http), do: "HTTP"
  def category_label(:s3), do: "S3"

  def category_label(category) do
    category
    |> to_string()
    |> String.split("_")
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end
