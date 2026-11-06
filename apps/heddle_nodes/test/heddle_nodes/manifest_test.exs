defmodule HeddleNodes.ManifestTest do
  use ExUnit.Case, async: true

  describe "manifest/0" do
    test "registers all built-in node modules" do
      assert HeddleNodes.available_nodes() == [
               HeddleNodes.Nodes.Start,
               HeddleNodes.Nodes.Webhook,
               HeddleNodes.Nodes.Schedule,
               HeddleNodes.Nodes.Variable,
               HeddleNodes.Nodes.Eval,
               HeddleNodes.Nodes.Csv,
               HeddleNodes.Nodes.HttpRequest,
               HeddleNodes.Nodes.Slack,
               HeddleNodes.Nodes.Email,
               HeddleNodes.Nodes.S3,
               HeddleNodes.Nodes.Ftp,
               HeddleNodes.Nodes.AIAgent,
               HeddleNodes.Nodes.Condition,
               HeddleNodes.Nodes.ForEach,
               HeddleNodes.Nodes.Logger,
               HeddleNodes.Nodes.Output,
               HeddleNodes.Nodes.RespondToWebhook
             ]
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
