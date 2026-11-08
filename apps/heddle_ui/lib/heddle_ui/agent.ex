defmodule HeddleUI.Agent do
  @moduledoc """
  The agent of Heddle, the same for every client.

  Each person has one conversation per flow, which lives on the server in a
  `HeddleUI.Agent.Session`. Clients only send messages and show what comes back, so
  the editor and Treadle see the same conversation, and closing either one doesn't
  stop the work.

  Subscribers receive `{:agent_event, event}`, and `HeddleUI.Agent.Transcript` tells
  what each event means.
  """

  alias HeddleCore.Accounts.Scope
  alias HeddleCore.AgentConversations
  alias HeddleUI.Agent.Session
  alias HeddleUI.Agent.Transcript

  @registry HeddleUI.Agent.Registry
  @supervisor HeddleUI.Agent.Supervisor

  def registry, do: @registry
  def supervisor, do: @supervisor
  def task_supervisor, do: HeddleUI.Agent.TaskSupervisor

  @doc "Whether something can answer here: the Claude Agent, or an LLM."
  def available?, do: HeddleUI.AgentChat.active?() or HeddleAI.LLM.configured?()

  @doc "Subscribes to the conversation about `flow_id`, even before it starts."
  def subscribe(%Scope{} = scope, flow_id) do
    Phoenix.PubSub.subscribe(HeddleCore.PubSub, topic(scope.user.id, flow_id))
  end

  @doc """
  Subscribes and returns the conversation so far.

  What arrived before the transcript is already in it, and would count twice.
  """
  def join(%Scope{} = scope, flow_id) do
    :ok = subscribe(scope, flow_id)
    transcript = transcript(scope, flow_id)
    flush()

    transcript
  end

  defp flush do
    receive do
      {:agent_event, _event} -> flush()
    after
      0 -> :ok
    end
  end

  @doc "Sends an event to whoever follows the conversation."
  def broadcast(user_id, flow_id, event) do
    Phoenix.PubSub.broadcast(HeddleCore.PubSub, topic(user_id, flow_id), {:agent_event, event})
  end

  @doc "Returns the conversation so far, empty if there is none."
  def transcript(%Scope{} = scope, flow_id) do
    case lookup(scope, flow_id) do
      nil -> Transcript.new()
      session -> Session.transcript(session)
    end
  end

  @doc """
  Sends a message, starting the conversation if needed.

  The agent changes the flow, so only those who can edit it may talk to it.
  """
  def send_message(%Scope{} = scope, flow_id, content) do
    with :ok <- may_edit(scope, flow_id) do
      scope |> ensure_session(flow_id) |> Session.send_message(content)
    end
  end

  defp may_edit(scope, flow_id) do
    case HeddleCore.Flows.fetch_for(scope, :edit, flow_id) do
      {:ok, _flow} -> :ok
      error -> error
    end
  end

  @doc """
  Starts a new conversation. While the agent works, it stays in the current one: leaving
  it would hide work that is still happening.
  """
  def new_conversation(%Scope{} = scope, flow_id) do
    with_session(scope, flow_id, &Session.new_conversation/1)
  end

  @doc "Goes back to a saved conversation."
  def open_conversation(%Scope{} = scope, flow_id, id) do
    with :ok <- may_edit(scope, flow_id) do
      scope |> ensure_session(flow_id) |> Session.open_conversation(id)
    end
  end

  @doc "Lists the saved conversations about a flow, the latest first."
  def conversations(%Scope{} = scope, flow_id) do
    AgentConversations.list_conversations(scope, flow_id)
  end

  @doc "Answers a request to run a flow: `\"once\"`, `\"always\"` or `\"deny\"`."
  def decide(%Scope{} = scope, flow_id, decision) do
    with :ok <- may_edit(scope, flow_id) do
      with_session(scope, flow_id, &Session.decide(&1, decision))
    end
  end

  @doc "Stops what the agent is doing."
  def stop(%Scope{} = scope, flow_id), do: with_session(scope, flow_id, &Session.stop/1)

  defp with_session(scope, flow_id, fun) do
    case lookup(scope, flow_id) do
      nil -> {:error, :not_found}
      session -> fun.(session)
    end
  end

  defp lookup(scope, flow_id) do
    case Registry.lookup(@registry, key(scope, flow_id)) do
      [{session, _value}] -> session
      [] -> nil
    end
  end

  defp ensure_session(scope, flow_id) do
    opts = [
      scope: scope,
      flow_id: flow_id,
      name: {:via, Registry, {@registry, key(scope, flow_id)}}
    ]

    case DynamicSupervisor.start_child(@supervisor, {Session, opts}) do
      {:ok, session} -> session
      {:error, {:already_started, session}} -> session
    end
  end

  defp key(scope, flow_id), do: {scope.user.id, to_string(flow_id)}

  defp topic(user_id, flow_id), do: "agent:#{user_id}:#{flow_id}"
end
