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
      assert length(actions) == 7
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

  describe "initial_assigns/0" do
    test "starts with the services collapsed, so the sidebar stays short" do
      collapsed = NodePaletteManager.initial_assigns()[:collapsed_node_categories]

      assert MapSet.equal?(collapsed, MapSet.new(Nodes.service_categories()))
    end
  end
end
