defmodule HeddleUI.FlowLive.AgentManager do
  @moduledoc """
  Socket reducers for the agent inside `FlowLive`.

  The conversation lives in `HeddleUI.Agent`: this only follows it. The agent reads the
  saved flow, so a message with unsaved changes on the canvas waits for them first.
  """
  import Phoenix.Component, only: [assign: 2, update: 3]
  import Phoenix.LiveView, only: [connected?: 1]

  alias HeddleUI.Agent
  alias HeddleUI.Agent.Transcript

  @doc "Default agent-related assigns, merged into the LiveView mount."
  def initial_assigns do
    [
      agent: Transcript.new(),
      pending_agent_message: nil,
      agent_history_open: false,
      agent_history: []
    ]
  end

  @doc """
  Opens the chat of this screen. It starts new, unless the agent is in the middle of
  something: then this is the screen that shows it.
  """
  def follow(socket) do
    if connected?(socket) do
      scope = socket.assigns.current_scope
      flow_id = socket.assigns.current_flow.id

      _result = Agent.new_conversation(scope, flow_id)
      assign(socket, agent: Agent.join(scope, flow_id))
    else
      socket
    end
  end

  def new_conversation(socket) do
    _result = Agent.new_conversation(socket.assigns.current_scope, socket.assigns.current_flow.id)
    assign(socket, agent_history_open: false)
  end

  def toggle_history(socket) do
    open? = not socket.assigns.agent_history_open

    conversations =
      if open? do
        Agent.conversations(socket.assigns.current_scope, socket.assigns.current_flow.id)
      else
        []
      end

    assign(socket, agent_history_open: open?, agent_history: conversations)
  end

  def open_conversation(socket, id) do
    %{current_scope: scope, current_flow: flow} = socket.assigns
    _result = Agent.open_conversation(scope, flow.id, id)

    assign(socket, agent_history_open: false)
  end

  # The canvas saves as it changes, and the agent reads the draft as the session of
  # the flow has it, so a message goes at once.
  def send_message(socket, content), do: deliver(socket, content)

  def apply_event(socket, event) do
    update(socket, :agent, &Transcript.reduce(&1, event))
  end

  def decide(socket, decision) do
    _result = Agent.decide(socket.assigns.current_scope, socket.assigns.current_flow.id, decision)
    socket
  end

  def stop(socket) do
    _result = Agent.stop(socket.assigns.current_scope, socket.assigns.current_flow.id)
    socket
  end

  defp deliver(socket, content) do
    _result =
      Agent.send_message(socket.assigns.current_scope, socket.assigns.current_flow.id, content)

    socket
  end
end
