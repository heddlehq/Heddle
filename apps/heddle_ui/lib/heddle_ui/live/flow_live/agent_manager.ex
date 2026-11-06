defmodule HeddleUI.FlowLive.AgentManager do
  @moduledoc """
  Socket reducers for the Claude Agent inside `FlowLive`.

  The agent reads the saved flow, so a message with unsaved changes on the canvas
  waits for them to be saved first.
  """
  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [push_event: 3, start_async: 3]

  alias HeddleUI.AgentChat
  alias HeddleUI.AIChat

  @doc "Default agent-related assigns, merged into the LiveView mount."
  def initial_assigns do
    [
      agent_session_id: nil,
      agent_session_started: false,
      agent_run: nil,
      pending_agent_message: nil,
      agent_confirmation: nil
    ]
  end

  def send_message(socket, content) do
    messages = socket.assigns.chat_messages ++ [{:user, content}, {:ai, ""}]
    socket = assign(socket, chat_messages: messages, chat_loading: true)

    if socket.assigns.has_changes do
      socket
      |> assign(pending_agent_message: content)
      |> push_event("request_graph_data", %{})
    else
      start(socket, content)
    end
  end

  @doc "Continues a message that was waiting for the canvas to be saved."
  def resume_pending(%{assigns: %{pending_agent_message: nil}} = socket), do: socket

  def resume_pending(socket) do
    content = socket.assigns.pending_agent_message

    socket
    |> assign(pending_agent_message: nil)
    |> start(content)
  end

  @doc "Drops a waiting message because the canvas could not be saved."
  def abort_pending(%{assigns: %{pending_agent_message: nil}} = socket), do: socket

  def abort_pending(socket) do
    assign(socket, pending_agent_message: nil, chat_loading: false)
  end

  @doc "Ends the current run, if the reply came from the agent."
  def finish(%{assigns: %{agent_run: nil}} = socket, _result), do: socket

  def finish(socket, result) do
    AgentChat.close(socket.assigns.agent_run)

    assign(socket,
      agent_run: nil,
      agent_confirmation: nil,
      agent_session_started: socket.assigns.agent_session_started or is_binary(result)
    )
  end

  def request_confirmation(socket, confirmation) do
    assign(socket, agent_confirmation: confirmation)
  end

  def decide(%{assigns: %{agent_confirmation: nil}} = socket, _approved?), do: socket

  def decide(socket, approved?) do
    %{ref: ref, reply_to: reply_to} = socket.assigns.agent_confirmation
    send(reply_to, {:agent_run_decision, ref, approved?})

    assign(socket, agent_confirmation: nil)
  end

  defp start(socket, content) do
    session_id = socket.assigns.agent_session_id || Ecto.UUID.generate()
    session = %{id: session_id, started?: socket.assigns.agent_session_started}
    run = AgentChat.open(socket.assigns.current_scope)
    flow = socket.assigns.current_flow
    parent = self()

    socket
    |> assign(agent_session_id: session_id, agent_run: run)
    |> start_async(:ai_stream, fn ->
      {:ok, result} = AgentChat.stream(run, flow, content, session)
      AIChat.consume_stream(result.stream, parent)
    end)
  end
end
