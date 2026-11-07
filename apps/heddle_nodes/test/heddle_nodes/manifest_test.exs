defmodule HeddleNodes.ManifestTest do
  use ExUnit.Case, async: true

  describe "manifest/0" do
    test "registers all built-in node modules" do
      nodes = HeddleNodes.available_nodes()

      for node <- [
            HeddleNodes.Nodes.Start,
            HeddleNodes.Nodes.Webhook,
            HeddleNodes.Nodes.Schedule,
            HeddleNodes.Nodes.Variable,
            HeddleNodes.Nodes.Eval,
            HeddleNodes.Nodes.Csv.Read,
            HeddleNodes.Nodes.Csv.Write,
            HeddleNodes.Nodes.HttpRequest,
            HeddleNodes.Nodes.AIAgent,
            HeddleNodes.Nodes.Condition,
            HeddleNodes.Nodes.ForEach,
            HeddleNodes.Nodes.Logger,
            HeddleNodes.Nodes.Output,
            HeddleNodes.Nodes.RespondToWebhook
          ] do
        assert node in nodes
      end
    end

    test "offers each action of a service as its own node" do
      services = HeddleNodes.Nodes.service_categories()
      actions = Enum.filter(HeddleNodes.get_definitions(), &(&1.category in services))
      names = Enum.map(actions, & &1.name)

      assert length(actions) == 76
      assert names == Enum.uniq(names)

      for action <- actions do
        assert [%{type: :credential} | fields] = action.ui_fields
        refute Enum.any?(fields, &(&1.name == :operation))
        assert action.name =~ ": "
      end
    end

    test "keeps the nodes of a database together, which the sidebar relies on" do
      groups =
        HeddleNodes.Nodes.nodes_by_category()[:database]
        |> Enum.chunk_by(& &1.group)
        |> Enum.map(&hd(&1).group)

      assert groups == [
               "SQL",
               "MongoDB",
               "Redis",
               "Elasticsearch",
               "DynamoDB",
               "Cassandra",
               "Neo4j"
             ]
    end

    test "shows the logo of the services that have one" do
      icon = fn name -> HeddleNodes.Nodes.get_node(name).icon end

      assert icon.("Slack: Send Message") == "logo-slack"
      assert icon.("Google Sheets: Read Rows") == "logo-google-sheets"
      assert icon.("S3: Upload File") == "logo-s3"
      assert icon.("MongoDB: Find Documents") == "logo-mongodb"
      assert icon.("FTP: Upload File") =~ "hero-"
      assert icon.("SQL: Run Query") =~ "hero-"
    end

    test "returns definitions with module references" do
      definitions = HeddleNodes.get_definitions()

      assert Enum.any?(definitions, fn definition ->
               definition.name == "Start" and definition.module == HeddleNodes.Nodes.Start
             end)
    end

    test "finds node modules by definition name" do
      assert HeddleNodes.get_node_module("Evaluate Code") == HeddleNodes.Nodes.Eval
      assert HeddleNodes.get_node_module("Missing") == nil
    end
  end
end
