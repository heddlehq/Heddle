defmodule HeddleUI.MCP.Tools.Chat do
  @moduledoc """
  Talks to the Heddle agent, which answers with the LLM of this server and can read
  and edit flows. Send the whole conversation in messages, each with a role of user
  or assistant and its content. When the reply has a run_request, the agent wants to
  run a flow: ask the user, and call run_flow if they agree.
  """

  use Anubis.Server.Component, type: :tool, name: "chat"

  alias HeddleAI.Agents.FlowCopilot
  alias HeddleAI.AI
  alias HeddleAI.LLM
  alias HeddleCore.ApiKeys
  alias HeddleCore.Flows
  alias HeddleUI.MCP.AgentTools
  alias HeddleUI.MCP.Tool

  schema do
    field :messages, {:list, :map}, required: true, description: "The conversation so far"
    field :flow_id, :string, description: "Flow open in the client, if any"
  end

  @impl true
  def execute(%{messages: messages} = params, frame) do
    Tool.authorize(frame, "workflows:read", fn scope ->
      cond do
        # The Claude Agent reaches these tools too, and has a model of its own.
        ApiKeys.agent_key?(frame.assigns.api_key) ->
          Tool.error("This tool isn't available to agents.", frame)

        not LLM.configured?() ->
          Tool.error("No LLM provider is configured on this server.", frame)

        true ->
          flow = params[:flow_id] && Flows.get_flow(scope, params[:flow_id])
          answer(messages, flow, frame)
      end
    end)
  end

  defp answer(messages, flow, frame) do
    ref = make_ref()

    result =
      AI.run(conversation(messages),
        system: FlowCopilot.system_prompt(flow),
        tools: AgentTools.build(frame, ref)
      )

    run_request = last_run_request(ref, nil)

    case result do
      {:ok, reply} -> Tool.reply(%{reply: reply, run_request: run_request}, frame)
      {:error, message} -> Tool.error(message, frame)
    end
  end

  defp conversation(messages) do
    for %{"role" => role, "content" => content} <- messages,
        role in ["user", "assistant"],
        is_binary(content) do
      %{role: role, content: content}
    end
  end

  defp last_run_request(ref, last) do
    receive do
      {^ref, :run_requested, request} -> last_run_request(ref, request)
    after
      0 -> last
    end
  end
end
