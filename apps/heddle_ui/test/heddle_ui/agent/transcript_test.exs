defmodule HeddleUI.Agent.TranscriptTest do
  use ExUnit.Case, async: true

  alias HeddleUI.Agent.Transcript

  defp play(events), do: Enum.reduce(events, Transcript.new(), &Transcript.reduce(&2, &1))

  test "joins the parts of a reply" do
    transcript =
      play([
        %{type: "user_message", text: "hi"},
        %{type: "text_delta", text: "Hel"},
        %{type: "text_delta", text: "lo"}
      ])

    assert [%{role: "user", text: "hi"}, %{role: "assistant", text: "Hello"}] = transcript.items
  end

  test "starts a new reply after a tool, so the order of the work shows" do
    transcript =
      play([
        %{type: "text_delta", text: "Checking."},
        %{type: "tool_started", id: "1", name: "get_flow", args: %{}},
        %{type: "tool_finished", id: "1", ok: true, output: "{}"},
        %{type: "text_delta", text: "Done."}
      ])

    assert [
             %{role: "assistant", text: "Checking."},
             %{role: "tool", status: "ok", output: "{}"},
             %{role: "assistant", text: "Done."}
           ] = transcript.items
  end

  test "marks a tool that failed" do
    transcript =
      play([
        %{type: "tool_started", id: "1", name: "get_flow", args: %{}},
        %{type: "tool_finished", id: "1", ok: false, output: "no"}
      ])

    assert [%{status: "error"}] = transcript.items
  end

  test "doesn't leave a tool spinning when the turn ends without it" do
    transcript =
      play([
        %{type: "tool_started", id: "1", name: "get_flow", args: %{}},
        %{type: "status", status: "idle"}
      ])

    assert [%{status: "error"}] = transcript.items
  end

  test "gives the same ids to everyone who plays the same events" do
    events = [%{type: "user_message", text: "a"}, %{type: "text_delta", text: "b"}]

    assert play(events) == play(events)
    assert ["item-1", "item-2"] = Enum.map(play(events).items, & &1.id)
  end

  test "is plain JSON all the way, for clients in other languages" do
    transcript =
      play([
        %{type: "tool_started", id: "1", name: "get_flow", args: %{"flow_id" => "1"}},
        %{type: "permission", permission: %{flow_name: "Flow"}}
      ])

    assert {:ok, _json} = Jason.encode(transcript)
  end
end
