defmodule HeddleUI.AIChatTest do
  use ExUnit.Case, async: true

  alias HeddleCore.Flows.GraphValidator
  alias HeddleUI.AIChat

  describe "to_api_messages/1" do
    test "maps roles and drops the trailing assistant placeholder" do
      messages = [{:user, "hi"}, {:ai, "hello"}, {:user, "again"}, {:ai, ""}]

      assert AIChat.to_api_messages(messages) == [
               %{role: "user", content: "hi"},
               %{role: "assistant", content: "hello"},
               %{role: "user", content: "again"}
             ]
    end
  end

  describe "append_chunk/2" do
    test "appends to the last assistant message" do
      messages = [{:user, "hi"}, {:ai, "par"}]

      assert AIChat.append_chunk(messages, "tial") == [{:user, "hi"}, {:ai, "partial"}]
    end

    test "leaves messages untouched when the last is not an assistant message" do
      messages = [{:ai, "done"}, {:user, "hi"}]

      assert AIChat.append_chunk(messages, "x") == messages
    end
  end

  describe "consume_stream/2" do
    test "forwards text deltas and returns the accumulated reply" do
      stream = [{:text_delta, "He"}, {:text_delta, "llo"}, {:finish, :stop}]

      assert AIChat.consume_stream(stream, self()) == "Hello"
      assert_received {:chat_stream_chunk, "He"}
      assert_received {:chat_stream_chunk, "llo"}
    end

    test "forwards and returns an error, halting the stream" do
      stream = [{:text_delta, "He"}, {:error, :boom}, {:text_delta, "never"}]

      assert AIChat.consume_stream(stream, self()) == {:error, :boom}
      assert_received {:chat_stream_chunk, "He"}
      assert_received {:chat_stream_error, :boom}
      refute_received {:chat_stream_chunk, "never"}
    end
  end

  describe "extract_create_flow_json/1" do
    test "parses a fenced JSON reply" do
      content = "```json\n{\"action\": \"create_flow\", \"nodes\": []}\n```"

      assert {:ok, %{"action" => "create_flow", "nodes" => []}} =
               AIChat.extract_create_flow_json(content)
    end

    test "parses JSON embedded in surrounding prose" do
      content =
        ~s(Sure! Here it is: {"action": "create_flow", "nodes": [], "connections": []} done)

      assert {:ok, %{"action" => "create_flow"}} = AIChat.extract_create_flow_json(content)
    end

    test "returns :error for non create_flow content" do
      assert :error = AIChat.extract_create_flow_json("just a normal reply")
      assert :error = AIChat.extract_create_flow_json(~s({"action": "something_else"}))
    end
  end

  describe "persistable_nodes/1" do
    test "keeps only the fields a saved flow accepts" do
      [node] =
        AIChat.persistable_nodes([
          %{"id" => "a", "type" => "Logger", "position" => %{}, "inputs" => %{}, "outputs" => %{}}
        ])

      assert node |> Map.keys() |> Enum.sort() == ~w(id position type)
    end

    test "produces nodes the graph validator accepts" do
      nodes =
        [%{"id" => "a", "type" => "Logger", "label" => "Log"}]
        |> AIChat.normalize_nodes()
        |> AIChat.persistable_nodes()

      assert GraphValidator.validate(nodes, []) == :ok
    end
  end

  describe "plan_proposed?/1" do
    test "finds the marker with or without brackets" do
      assert AIChat.plan_proposed?("Does that work? [PLAN_PROPOSED]")
      assert AIChat.plan_proposed?("Does that work? plan_proposed")
    end

    test "is false for a regular reply" do
      refute AIChat.plan_proposed?("Hello! How can I help?")
    end
  end

  describe "display_text/1" do
    test "removes the marker" do
      assert AIChat.display_text("Does that work? [PLAN_PROPOSED]") == "Does that work?"
    end

    test "removes the start of a marker still streaming" do
      assert AIChat.display_text("Does that work? [PLAN_PRO") == "Does that work?"
      assert AIChat.display_text("Does that work? [") == "Does that work?"
    end

    test "drops Markdown bold but keeps a lone operator" do
      assert AIChat.display_text("- **Add a Logger**: logs it") == "- Add a Logger: logs it"
      assert AIChat.display_text("Computes 2 ** 3") == "Computes 2 ** 3"
    end

    test "keeps line breaks and brackets inside the text" do
      text = "- Add [Logger]\n- Add Webhook"

      assert AIChat.display_text(text) == text
    end
  end

  describe "flow_json?/1" do
    test "recognizes JSON from its first characters" do
      assert AIChat.flow_json?(~s({"act))
      assert AIChat.flow_json?("  ```json\n{")
    end

    test "recognizes the action inside surrounding text" do
      assert AIChat.flow_json?(~s(Here it is: {"action": "create_flow"}))
    end

    test "is false for a plan" do
      refute AIChat.flow_json?("- Add a Logger node")
    end
  end

  describe "normalize_nodes/1" do
    test "fills defaults and flattens control values" do
      raw = [
        %{"id" => "a", "name" => "Webhook", "controls" => %{"path" => %{"value" => "/in"}}},
        %{"id" => "b", "name" => "Log"}
      ]

      assert [first, second] = AIChat.normalize_nodes(raw)

      assert first["id"] == "a"
      assert first["type"] == "Webhook"
      assert first["label"] == "Webhook"
      # control value maps are flattened to their raw value
      assert first["controls"] == %{"path" => "/in"}
      assert second["type"] == "Log"
    end

    test "normalizes Evaluate Code controls" do
      raw = [%{"id" => "a", "name" => "Evaluate Code", "controls" => %{"code" => "1 + 1"}}]

      assert [node] = AIChat.normalize_nodes(raw)

      assert node["controls"]["code_elixir"] == "1 + 1"
      assert node["controls"]["code_python"] == ""
      assert node["controls"]["language"] == "elixir"
      refute Map.has_key?(node["controls"], "code")
    end

    test "normalizes Output controls with defaults" do
      raw = [%{"id" => "a", "name" => "Output", "controls" => %{}}]

      assert [node] = AIChat.normalize_nodes(raw)

      assert node["controls"] == %{"status" => "success"}
    end

    test "reads label and controls from a nested data map" do
      raw = [
        %{
          "id" => "a",
          "name" => "Log",
          "data" => %{"label" => "My Log", "x" => 5, "y" => 9, "level" => "info"}
        }
      ]

      assert [node] = AIChat.normalize_nodes(raw)

      assert node["label"] == "My Log"
      # controls fall back to the data map (minus reserved keys)
      assert node["controls"] == %{"level" => "info"}
    end

    test "leaves the position to the layout" do
      raw = [%{"id" => "a", "name" => "Log", "position" => %{"x" => 1, "y" => 2}}]

      assert [node] = AIChat.normalize_nodes(raw)

      refute Map.has_key?(node, "position")
    end
  end
end
