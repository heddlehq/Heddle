defmodule HeddleCore.Flows.GraphValidatorTest do
  use ExUnit.Case, async: true

  alias HeddleCore.Flows.GraphValidator

  defmodule Manifest do
    def get_definitions do
      [
        %{
          name: "Start",
          inputs: [],
          outputs: ["exec"]
        },
        %{
          name: "Output",
          inputs: ["exec"],
          outputs: []
        },
        %{
          name: "Schedule",
          inputs: [],
          outputs: ["exec"]
        }
      ]
    end
  end

  @valid_nodes [
    %{
      "id" => "start",
      "type" => "Start",
      "label" => "Start",
      "controls" => %{},
      "position" => %{"x" => 0, "y" => 0}
    },
    %{
      "id" => "output",
      "type" => "Output",
      "label" => "Output",
      "controls" => %{},
      "position" => %{"x" => 200, "y" => 0}
    }
  ]

  @valid_connections [
    %{
      "source" => "start",
      "sourceOutput" => "exec",
      "target" => "output",
      "targetInput" => "exec"
    }
  ]

  describe "validate/3" do
    test "accepts an empty graph without loading a manifest" do
      assert GraphValidator.validate([], [], manifest: MissingManifest) == :ok
    end

    test "accepts a node without position and a connection without target input" do
      nodes = [
        %{"id" => "a", "type" => "Start", "controls" => %{}},
        %{"id" => "b", "type" => "Output", "controls" => %{}}
      ]

      connection = %{"source" => "a", "sourceOutput" => "exec", "target" => "b"}

      assert GraphValidator.validate(nodes, [connection], manifest: Manifest) == :ok
    end

    test "refuses a position that isn't one" do
      node = %{"id" => "a", "type" => "Start", "controls" => %{}, "position" => %{"x" => "1"}}

      assert {:error, :nodes, "contains a node with invalid position"} =
               GraphValidator.validate([node], [], manifest: Manifest)
    end

    test "treats an integer id and the same id as a string as the same node" do
      nodes = [
        %{"id" => 1, "type" => "Start", "controls" => %{}},
        %{"id" => "1", "type" => "Start", "controls" => %{}}
      ]

      assert {:error, :nodes, "contains duplicate node ids"} =
               GraphValidator.validate(nodes, [], manifest: Manifest)
    end

    test "accepts a valid graph" do
      assert GraphValidator.validate(@valid_nodes, @valid_connections, manifest: Manifest) == :ok
    end

    test "rejects a Schedule node with an invalid cron expression" do
      schedule = fn cron ->
        [
          %{
            "id" => "s",
            "type" => "Schedule",
            "label" => "Schedule",
            "position" => %{"x" => 0, "y" => 0},
            "controls" => %{"cron" => cron}
          }
        ]
      end

      assert GraphValidator.validate(schedule.("0 9 * * 1-5"), [], manifest: Manifest) == :ok

      for cron <- ["", "soon", "61 * * * *", "@reboot"] do
        assert {:error, :nodes, message} =
                 GraphValidator.validate(schedule.(cron), [], manifest: Manifest)

        assert message =~ "cron"
      end
    end

    test "rejects node types missing from manifest" do
      nodes = [
        %{
          "id" => "bad",
          "type" => "Missing",
          "controls" => %{},
          "position" => %{"x" => 0, "y" => 0}
        }
      ]

      assert {:error, :nodes, "contains unknown node type"} =
               GraphValidator.validate(nodes, [], manifest: Manifest)
    end

    test "rejects dangerous unknown node fields" do
      [node | rest] = @valid_nodes
      nodes = [Map.put(node, "module", "Elixir.System") | rest]

      assert {:error, :nodes, "contains unknown node fields"} =
               GraphValidator.validate(nodes, @valid_connections, manifest: Manifest)
    end

    test "rejects dangerous unknown connection fields" do
      [connection] = @valid_connections
      connections = [Map.put(connection, "eval", "System.cmd")]

      assert {:error, :connections, "contains unknown connection fields"} =
               GraphValidator.validate(@valid_nodes, connections, manifest: Manifest)
    end

    test "rejects connections to missing nodes" do
      [connection] = @valid_connections
      connections = [%{connection | "target" => "missing"}]

      assert {:error, :connections, "references a missing node"} =
               GraphValidator.validate(@valid_nodes, connections, manifest: Manifest)
    end

    test "rejects connections with unknown source output" do
      [connection] = @valid_connections
      connections = [%{connection | "sourceOutput" => "missing"}]

      assert {:error, :connections, "references an unknown source output"} =
               GraphValidator.validate(@valid_nodes, connections, manifest: Manifest)
    end

    test "rejects connections with unknown target input" do
      [connection] = @valid_connections
      connections = [%{connection | "targetInput" => "missing"}]

      assert {:error, :connections, "references an unknown target input"} =
               GraphValidator.validate(@valid_nodes, connections, manifest: Manifest)
    end

    test "accepts a node's settings, and refuses ones it doesn't take" do
      [start, output] = @valid_nodes
      retrying = Map.put(start, "settings", %{"retries" => 2, "on_error" => "continue"})

      assert GraphValidator.validate([retrying, output], @valid_connections, manifest: Manifest) ==
               :ok

      wrong = Map.put(start, "settings", %{"retries" => 99})

      assert {:error, :nodes, "contains a node with invalid settings"} =
               GraphValidator.validate([wrong, output], @valid_connections, manifest: Manifest)
    end

    test "accepts a connection from the error output that a node's settings give it" do
      [start, output] = @valid_nodes
      [connection] = @valid_connections
      from_error = %{connection | "sourceOutput" => "error"}

      assert {:error, :connections, "references an unknown source output"} =
               GraphValidator.validate(@valid_nodes, [from_error], manifest: Manifest)

      start = Map.put(start, "settings", %{"on_error" => "output"})
      assert GraphValidator.validate([start, output], [from_error], manifest: Manifest) == :ok
    end
  end

  describe "validate_comments/1" do
    @comment %{
      "id" => "note",
      "kind" => "note",
      "color" => "yellow",
      "text" => "Calls the billing API",
      "width" => 240,
      "height" => 140,
      "position" => %{"x" => 10, "y" => 20.5}
    }

    test "accepts no comments, and comments without text" do
      assert GraphValidator.validate_comments([]) == :ok
      assert GraphValidator.validate_comments([@comment]) == :ok
      assert GraphValidator.validate_comments([%{@comment | "text" => ""}]) == :ok
    end

    test "accepts every kind and color" do
      for kind <- ~w(title text note section), color <- ~w(default yellow green blue red) do
        comment = %{@comment | "kind" => kind, "color" => color}

        assert GraphValidator.validate_comments([comment]) == :ok
      end
    end

    test "accepts what a section holds, and whether it runs with the flow" do
      section = %{@comment | "kind" => "section"}

      for fields <- [
            %{"manual" => true, "nodes" => ["a", 2]},
            %{"manual" => false, "nodes" => []}
          ] do
        assert GraphValidator.validate_comments([Map.merge(section, fields)]) == :ok
      end
    end

    test "rejects section fields that are wrong, or on what isn't a section" do
      section = %{@comment | "kind" => "section"}

      invalid = [
        Map.put(section, "manual", "yes"),
        Map.put(section, "nodes", "a"),
        Map.put(section, "nodes", [""]),
        Map.put(@comment, "manual", true),
        Map.put(@comment, "nodes", ["a"])
      ]

      for comment <- invalid do
        assert {:error, :comments, "contains an invalid comment"} =
                 GraphValidator.validate_comments([comment])
      end
    end

    test "rejects what isn't a list of objects" do
      assert {:error, :comments, "must be a list"} = GraphValidator.validate_comments(%{})
      assert {:error, :comments, _message} = GraphValidator.validate_comments(["note"])
    end

    test "rejects duplicate ids" do
      assert {:error, :comments, "contains duplicate comment ids"} =
               GraphValidator.validate_comments([@comment, @comment])
    end

    test "rejects a comment with missing, invalid or unknown fields" do
      invalid = [
        Map.delete(@comment, "id"),
        Map.delete(@comment, "text"),
        Map.delete(@comment, "kind"),
        %{@comment | "kind" => "image"},
        %{@comment | "color" => "#ff0000"},
        %{@comment | "text" => 1},
        %{@comment | "position" => %{"x" => "10", "y" => 20}},
        %{@comment | "width" => 0},
        %{@comment | "height" => "140"},
        Map.put(@comment, "script", "x")
      ]

      for comment <- invalid do
        assert {:error, :comments, "contains an invalid comment"} =
                 GraphValidator.validate_comments([comment])
      end
    end
  end
end
