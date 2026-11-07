defmodule HeddleUI.ChatComponentTest do
  use HeddleUI.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias HeddleUI.Agent.Transcript
  alias HeddleUI.Components.ChatComponent

  defp chat(events, opts \\ []) do
    agent = Enum.reduce(events, Transcript.new(), &Transcript.reduce(&2, &1))

    render_component(ChatComponent, [id: "chat", open: true, agent: agent] ++ opts)
  end

  defp tool(name, args \\ %{}), do: %{type: "tool_started", id: "t1", name: name, args: args}

  test "shows replies as they are" do
    assert chat([%{type: "text_delta", text: "Hello"}]) =~ "Hello"
  end

  test "adds no space of its own around a reply, which keeps its line breaks" do
    html = chat([%{type: "text_delta", text: "\n\nOne\n\nTwo\n"}])

    assert html =~ ~s(<span class="whitespace-pre-wrap">One\n\nTwo</span>)
  end

  test "says what a tool is doing while it runs" do
    html = chat([tool("get_flow")])

    assert html =~ "Reading the flow"
    assert html =~ ~s(data-status="running")
  end

  test "shows how a test ended without opening it" do
    output = Jason.encode!(%{status: "failed", error: %{message: "key :x not found"}})

    html = chat([tool("test_flow"), %{type: "tool_finished", id: "t1", ok: true, output: output}])

    assert html =~ "key :x not found"
  end

  test "keeps what the tool got and returned in the details" do
    html =
      chat([
        tool("test_flow", %{"webhook" => %{"body" => %{"x" => 2}}}),
        %{type: "tool_finished", id: "t1", ok: true, output: ~s({"status":"succeeded"})}
      ])

    assert html =~ "agent-tool-details-t1"
    assert html =~ "succeeded"
  end

  test "offers to stop while it works, and to send when it doesn't" do
    assert chat([%{type: "status", status: "running"}]) =~ "agent-stop"
    refute chat([]) =~ "agent-stop"
  end

  test "counts as working while the message waits for the canvas to save" do
    assert chat([], waiting: true) =~ "agent-working"
  end

  test "asks to run a flow" do
    html = chat([%{type: "permission", permission: %{flow_name: "Sum"}}])

    assert html =~ "agent-run-always"
    assert html =~ "Sum"
  end

  test "lists the previous chats instead of the conversation" do
    conversation = %{id: "c1", title: "Fix the sum", updated_at: ~U[2026-11-07 06:00:00Z]}

    html =
      chat([%{type: "text_delta", text: "Current"}], history_open: true, history: [conversation])

    assert html =~ "Fix the sum"
    refute html =~ "Current"
  end

  test "shows a failure in the conversation" do
    assert chat([%{type: "failed", message: "no credits"}]) =~ "no credits"
  end
end
