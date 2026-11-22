defmodule HeddleUI.FlowLive.NodePaletteManagerTest do
  use ExUnit.Case, async: true

  alias HeddleNodes.Nodes
  alias HeddleUI.FlowLive.NodePaletteManager

  describe "nodes_by_category/1" do
    test "keeps the services together and in order, after HTTP Request" do
      categories = "" |> NodePaletteManager.nodes_by_category() |> Enum.map(&elem(&1, 0))
      position = Enum.find_index(categories, &(&1 == :http))

      services = Nodes.service_categories()

      assert Enum.slice(categories, position + 1, length(services)) == services
      assert List.last(categories) == :utility
    end

    test "finds a database by a name that's only in the description" do
      assert [{:database, nodes}] = NodePaletteManager.nodes_by_category("postgresql")
      assert Enum.any?(nodes, &(&1.name == "SQL: Run Query"))
    end

    test "finds the actions of a service by its name" do
      assert [{:slack, actions}] = NodePaletteManager.nodes_by_category("slack")
      assert length(actions) == 8
    end
  end

  describe "filter_nodes/1" do
    test "finds a node by what it does" do
      assert [%{name: "AI: Edit Image"}, %{name: "AI: Generate Image"}] =
               "nano banana"
               |> NodePaletteManager.filter_nodes()
               |> Enum.sort_by(& &1.name)
    end
  end

  describe "with the integrations a workspace installed" do
    test "shows the core and only the installed integrations" do
      categories =
        "" |> NodePaletteManager.nodes_by_category(MapSet.new(["slack"])) |> Map.new()

      assert Map.has_key?(categories, :http)
      assert length(categories[:slack]) == 8
      refute Map.has_key?(categories, :google_sheets)
      assert Enum.map(categories[:database], & &1.group) |> Enum.uniq() == ["Spool"]
    end

    test "a search offers the integrations that aren't installed" do
      installed = MapSet.new(["slack"])

      assert [] = NodePaletteManager.nodes_by_category("sheets", installed)

      assert [%{id: "google_sheets"}] =
               NodePaletteManager.uninstalled_integrations("sheets", installed)

      assert [] = NodePaletteManager.uninstalled_integrations("slack", installed)
      assert [] = NodePaletteManager.uninstalled_integrations("", installed)
    end

    test "starts with the installed services open" do
      assigns = NodePaletteManager.initial_assigns(MapSet.new(["slack"]))

      assert MapSet.size(assigns[:collapsed_node_categories]) == 0
      refute Enum.any?(assigns[:filtered_nodes], &(&1.category == :google_sheets))
    end
  end
end
