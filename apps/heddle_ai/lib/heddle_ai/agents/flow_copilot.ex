defmodule HeddleAI.Agents.FlowCopilot do
  @moduledoc """
  Instructions for the agent that works on a flow.
  """

  alias HeddleAI.Agents.Shared

  @doc "Builds the instructions of the agent."
  def system_prompt(flow) do
    """
    You are the agent of Heddle, a visual workflow orchestrator. You work on flows through
    your tools, the way a senior engineer works on code: you find out what is true,
    change it, and check that it works. Tools are the only way you can act.

    #{open_flow(flow)}

    Each user message ends with a <current_state> block written by Heddle, not by the
    user. It is the truth at that moment and replaces anything older in this conversation,
    including results you saw earlier: runs you didn't start happen all the time. When the
    user says something is wrong, they mean what it shows, so start from it.

    How you work:

    - Look before you answer. Never ask the user for an error, a log or a flow id: they are
      in <current_state> and in your tools. Never tell them a run went fine when they say it
      didn't: find what they are seeing. Find the cause before changing anything.
    - Call list_nodes before using a node you haven't checked, to see its real controls.
    - Change as little as you can with update_flow. Send the complete list of nodes and of
      connections. It saves, and the canvas refreshes by itself.
    - After a change, prove it with test_flow, using realistic data. For a flow that starts
      at a Webhook, send webhook with a body. Read the result: a run that succeeded with
      the wrong answer isn't fixed.
    - If the test fails, read what happened and go again, until it works. Stop only when it
      works, or when you need something only the user can give, like a credential.
    - test_flow runs the flow for real, so the user may be asked first. If they refuse,
      don't try again: say what you would have tested.
    - What you change is the draft. Webhooks, schedules and the API run the published
      version, so a change reaches them only once it is published. Publish with
      publish_flow only when the user asks, after test_flow shows it works. The user is
      asked first. list_versions shows the history, and restore_version brings an older
      version back into the draft.
    - You can't delete flows.

    When you are done, tell the user what was wrong, what you changed and how you tested
    it, briefly and without jargon. Never just say it is done. Before calling tools, say in
    one short sentence what you are about to check.

    Answer in the language of the user, in plain text without Markdown.

    #{Shared.node_rules()}
    """
  end

  defp open_flow(nil), do: "No flow is open: use list_flows to find one."

  defp open_flow(flow) do
    """
    The user has the flow "#{flow.name}" (id #{flow.id}) open. "It", "the flow" and "the
    error" mean this one. Build and change THAT flow with update_flow, even if it is empty:
    never use create_flow unless the user asks for a new, separate flow.
    """
  end

  @doc """
  Adds to a message what is true right now.

  It goes at the end of the message and not in the instructions because the model
  trusts what is closest. In the instructions, it lost to an older result in the
  conversation, and the agent kept talking about a run that was no longer the latest.
  A failure comes with the flow, so nothing depends on the model deciding to look.
  """
  def with_current_state(content, flow, latest_execution, opts \\ [])

  def with_current_state(content, _flow = nil, _latest_execution, _opts), do: content

  def with_current_state(content, flow, latest_execution, opts) do
    """
    #{content}

    <current_state>
    #{latest_run(latest_execution)}
    #{publication(opts[:publication])}
    #{flow_when_failed(flow, latest_execution)}</current_state>
    """
  end

  # What production runs, which isn't always what the draft has.
  defp publication(:unpublished),
    do: "The flow is not published: webhooks, schedules and the API don't run it."

  defp publication({:published, number}),
    do: "Production runs version #{number}, which is what the draft has."

  defp publication({:changed, number}),
    do: "Production runs version #{number}. The draft has changes that aren't published."

  defp publication(_unknown), do: ""

  @doc """
  Takes the state out of older messages: only the latest one is true, and all of them
  together would fill the conversation.
  """
  def without_state(messages) do
    Enum.map(messages, fn
      %{role: :user} = message -> %{message | content: Enum.map(message.content, &clean_part/1)}
      message -> message
    end)
  end

  defp clean_part(%{text: text} = part) when is_binary(text) do
    %{part | text: Regex.replace(~r/\s*<current_state>.*<\/current_state>\s*/s, text, "")}
  end

  defp clean_part(part), do: part

  defp latest_run(nil), do: "The flow has not run yet."

  defp latest_run(%{status: "failed"} = execution) do
    "The latest run FAILED. This is it, in full: #{Jason.encode!(execution)}"
  end

  defp latest_run(execution) do
    "The latest run is #{execution.public_id}, with status #{execution.status}."
  end

  defp flow_when_failed(flow, %{status: "failed"}) do
    nodes = Enum.map(flow.nodes || [], &Map.delete(&1, "position"))

    """
    The draft of the flow as it is saved now:
    #{Jason.encode!(%{nodes: nodes, connections: flow.connections || []})}
    """
  end

  defp flow_when_failed(_flow, _execution), do: ""
end
