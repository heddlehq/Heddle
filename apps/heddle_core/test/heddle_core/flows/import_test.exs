defmodule HeddleCore.Flows.ImportTest do
  use ExUnit.Case, async: true

  alias HeddleCore.Flows.Import

  defmodule Manifest do
    def get_definitions do
      [
        %{name: "Webhook", inputs: [], outputs: [:exec], ui_fields: []},
        %{
          name: "Slack: Send Message",
          inputs: [:exec],
          outputs: ["success", "error"],
          ui_fields: [
            %{type: :credential, name: :credential, label: "Credential"},
            %{type: :text, name: :channel, label: "Channel"}
          ]
        }
      ]
    end
  end

  @nodes [
    %{
      "id" => "hook",
      "type" => "Webhook",
      "label" => "New lead",
      "controls" => %{"path" => "/leads"},
      "position" => %{"x" => 0, "y" => 0}
    },
    %{
      "id" => "tell",
      "type" => "Slack: Send Message",
      "label" => "Tell sales",
      "controls" => %{"credential" => "42", "channel" => "#sales"},
      "position" => %{"x" => 200, "y" => 0}
    }
  ]

  @connections [
    %{"source" => "hook", "sourceOutput" => "exec", "target" => "tell", "targetInput" => "exec"}
  ]

  @note %{
    "id" => "note",
    "kind" => "note",
    "color" => "yellow",
    "text" => "Leads go to #sales",
    "width" => 240,
    "height" => 140,
    "position" => %{"x" => 0, "y" => -200}
  }

  defp read(value), do: value |> Jason.encode!() |> Import.read(manifest: Manifest)

  describe "read/2" do
    test "reads a flow as Heddle saves it" do
      assert {:ok, graph} = read(%{nodes: @nodes, connections: @connections, comments: [@note]})

      assert Enum.map(graph["nodes"], & &1["id"]) == ["hook", "tell"]
      assert graph["connections"] == @connections
      assert graph["comments"] == [@note]
    end

    test "reads a flow as the API answers it, and one without comments" do
      assert {:ok, graph} =
               read(%{data: %{id: 7, name: "Leads", nodes: @nodes, connections: @connections}})

      assert length(graph["nodes"]) == 2
      assert graph["comments"] == []
    end

    test "empties the fields that pick a credential, and keeps the others" do
      assert {:ok, graph} = read(%{nodes: @nodes, connections: @connections})

      tell = Enum.find(graph["nodes"], &(&1["id"] == "tell"))
      assert tell["controls"] == %{"credential" => "", "channel" => "#sales"}
    end

    test "refuses what isn't JSON, or isn't a flow" do
      assert {:error, :invalid_json} = Import.read("{nodes", manifest: Manifest)
      assert {:error, :not_a_flow} = read(%{name: "Leads"})
      assert {:error, :not_a_flow} = read([1, 2, 3])
      assert {:error, :not_a_flow} = read(%{nodes: "hook", connections: []})
    end

    test "refuses a flow the validator would refuse" do
      unknown = [%{"id" => "x", "type" => "Teleport", "label" => "x", "controls" => %{}}]
      assert {:error, message} = read(%{nodes: unknown, connections: []})
      assert message =~ "unknown"

      wrong_output = [%{hd(@connections) | "sourceOutput" => "nope"}]
      assert {:error, _message} = read(%{nodes: @nodes, connections: wrong_output})

      assert {:error, _message} = read(%{nodes: [1], connections: []})

      assert {:error, _message} =
               read(%{nodes: @nodes, connections: @connections, comments: [%{"id" => "x"}]})
    end
  end
end
