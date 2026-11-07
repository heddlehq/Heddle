defmodule HeddleAI.ClaudeAgent.EventsTest do
  use ExUnit.Case, async: true

  alias HeddleAI.ClaudeAgent.Events

  # Shapes recorded from `claude -p --output-format stream-json`.
  defp stream_event(event), do: Jason.encode!(%{type: "stream_event", event: event})

  test "reads text deltas" do
    line =
      stream_event(%{
        type: "content_block_delta",
        index: 0,
        delta: %{type: "text_delta", text: "pong"}
      })

    assert Events.parse(line) == [{:text_delta, "pong"}]
  end

  test "ignores the other events" do
    assert Events.parse(~s({"type":"system","subtype":"init"})) == []
    assert Events.parse(stream_event(%{type: "message_stop"})) == []
    assert Events.parse(~s({"type":"rate_limit_event"})) == []
  end

  test "a successful result adds nothing, the text already streamed" do
    line = ~s({"type":"result","subtype":"success","is_error":false,"result":"pong"})

    assert Events.parse(line) == []
  end

  test "reports a failed result" do
    line = ~s({"type":"result","subtype":"error_during_execution","is_error":true})

    assert [{:error, message}] = Events.parse(line)
    assert message =~ "error_during_execution"
  end

  test "explains the spending limit" do
    line = ~s({"type":"result","subtype":"error_max_budget_usd","is_error":true})

    assert [{:error, "This message reached the spending limit."}] = Events.parse(line)
  end

  test "drops lines that aren't JSON" do
    assert Events.parse("some warning on stderr") == []
  end

  describe "tools" do
    test "reports a tool the agent called, without the MCP prefix" do
      line =
        Jason.encode!(%{
          type: "assistant",
          message: %{
            content: [
              %{type: "text", text: "Looking"},
              %{type: "tool_use", id: "t1", name: "mcp__heddle__get_flow", input: %{flow_id: "1"}}
            ]
          }
        })

      assert [{:tool_started, %{id: "t1", name: "get_flow", args: %{"flow_id" => "1"}}}] =
               Events.parse(line)
    end

    test "reports what the tool returned" do
      line =
        Jason.encode!(%{
          type: "user",
          message: %{
            content: [
              %{
                type: "tool_result",
                tool_use_id: "t1",
                content: [%{type: "text", text: "a flow"}]
              }
            ]
          }
        })

      assert [{:tool_finished, %{id: "t1", ok?: true, output: "a flow"}}] = Events.parse(line)
    end

    test "reports a tool that failed" do
      line =
        Jason.encode!(%{
          type: "user",
          message: %{
            content: [%{type: "tool_result", tool_use_id: "t1", content: "no", is_error: true}]
          }
        })

      assert [{:tool_finished, %{ok?: false, output: "no"}}] = Events.parse(line)
    end
  end
end
