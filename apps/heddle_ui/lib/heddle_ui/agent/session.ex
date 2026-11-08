defmodule HeddleUI.Agent.Session do
  @moduledoc """
  One conversation about a flow.

  Each message runs as a task, so this process stays free to take a stop or an answer,
  and a crash in a turn ends that turn and not the conversation. It belongs to the
  server: nothing here depends on a client being connected, and it goes away after
  some time with nothing to do.

  Running a flow has real effects, so the agent asks first. Its key is registered to
  this process, which is where `HeddleUI.AgentChat.confirm_run/2` comes to ask.
  """

  use GenServer, restart: :temporary

  require Logger

  alias HeddleAI.Agents.FlowCopilot
  alias HeddleAI.Harness
  alias HeddleCore.Accounts.Scope
  alias HeddleCore.AgentConversations
  alias HeddleCore.ApiKeys
  alias HeddleCore.Executions
  alias HeddleCore.Flows
  alias HeddleUI.Agent
  alias HeddleUI.Agent.Transcript
  alias HeddleUI.AgentChat
  alias HeddleUI.MCP.AgentTools
  alias ReqLLM.Context

  @idle_timeout to_timeout(minute: 30)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))
  end

  def transcript(session), do: GenServer.call(session, :transcript)

  @doc "Starts over, unless a turn is running. The conversation so far stays saved."
  def new_conversation(session), do: GenServer.call(session, :new_conversation)

  @doc "Goes back to a saved conversation, unless a turn is running."
  def open_conversation(session, id), do: GenServer.call(session, {:open_conversation, id})

  @doc "Returns `:ok`, or `{:error, :busy}` while a turn is running."
  def send_message(session, content), do: GenServer.call(session, {:send_message, content})

  def decide(session, decision), do: GenServer.call(session, {:decide, decision})

  def stop(session), do: GenServer.call(session, :stop)

  @impl true
  def init(opts) do
    state = %{
      scope: Keyword.fetch!(opts, :scope),
      flow_id: Keyword.fetch!(opts, :flow_id),
      transcript: Transcript.new(),
      history: [],
      turn: nil,
      question: nil,
      runs_allowed?: false,
      seen_failure: nil,
      conversation_id: nil,
      claude: %{id: Ecto.UUID.generate(), started?: false}
    }

    {:ok, state, @idle_timeout}
  end

  @impl true
  def handle_call(:transcript, _from, state), do: reply(state.transcript, state)

  def handle_call(:new_conversation, _from, %{turn: turn} = state) when turn != nil do
    reply({:error, :busy}, state)
  end

  def handle_call(:new_conversation, _from, state) do
    reply(:ok, restart(state, nil, [], []))
  end

  def handle_call({:open_conversation, _id}, _from, %{turn: turn} = state) when turn != nil do
    reply({:error, :busy}, state)
  end

  def handle_call({:open_conversation, id}, _from, state) do
    case AgentConversations.get_conversation(state.scope, state.flow_id, id) do
      nil ->
        reply({:error, :not_found}, state)

      conversation ->
        items = Enum.map(conversation.items, &Transcript.item_from_saved/1)
        reply(:ok, restart(state, conversation.id, items, history_from(items)))
    end
  end

  def handle_call({:send_message, _content}, _from, %{turn: turn} = state) when turn != nil do
    reply({:error, :busy}, state)
  end

  def handle_call({:send_message, content}, _from, state) do
    state =
      state
      |> emit(%{type: "user_message", text: content})
      |> emit(%{type: "status", status: "running"})
      |> start_turn(content)

    reply(:ok, state)
  end

  def handle_call({:decide, _decision}, _from, %{question: nil} = state) do
    reply({:error, :nothing_to_decide}, state)
  end

  def handle_call({:decide, decision}, _from, state) do
    state =
      state
      |> answer(decision != "deny")
      |> Map.update!(:runs_allowed?, &(&1 or decision == "always"))

    reply(:ok, state)
  end

  def handle_call(:stop, _from, %{turn: nil} = state), do: reply(:ok, state)

  def handle_call(:stop, _from, state) do
    Task.Supervisor.terminate_child(Agent.task_supervisor(), state.turn.task.pid)
    Process.demonitor(state.turn.task.ref, [:flush])

    reply(:ok, end_turn(state, {:stopped, state.turn.content}))
  end

  @impl true
  def handle_info({:harness_event, {:failure_read, id}}, state) do
    noreply(Map.put(state, :seen_failure, id))
  end

  def handle_info({:harness_event, event}, state), do: noreply(emit(state, to_event(event)))

  # Allowing every run doesn't allow changing what production runs.
  def handle_info(
        {:agent_run_confirmation, %{action: "run"} = question},
        %{runs_allowed?: true} = state
      ) do
    send(question.reply_to, {:agent_run_decision, question.ref, true})
    noreply(state)
  end

  def handle_info({:agent_run_confirmation, question}, state) do
    permission = %{
      flow_name: question.flow_name,
      action: Map.get(question, :action, "run"),
      version: Map.get(question, :version)
    }

    state = emit(state, %{type: "permission", permission: permission})
    noreply(%{state | question: question})
  end

  def handle_info({ref, result}, %{turn: %{task: %{ref: ref}}} = state) do
    Process.demonitor(ref, [:flush])
    noreply(end_turn(state, result))
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{turn: %{task: %{ref: ref}}} = state) do
    Logger.warning("An agent turn crashed: #{inspect(reason)}")
    noreply(end_turn(state, {:error, "The agent stopped unexpectedly."}))
  end

  def handle_info(:timeout, %{turn: nil} = state), do: {:stop, :normal, state}

  def handle_info(_message, state), do: noreply(state)

  defp start_turn(state, content) do
    flow = Flows.get_flow(state.scope, state.flow_id)
    run = AgentChat.open(state.scope, flow && flow.workspace_id)
    # Whoever is on the canvas sees the agent there while it works.
    if flow && state.scope.user, do: HeddleUI.FlowPresence.track_agent(flow.id, state.scope.user)
    session = self()
    on_event = &send(session, {:harness_event, &1})

    turn =
      state
      |> Map.take([:scope, :flow_id, :history, :claude])
      |> Map.put(:seen_failure, Map.get(state, :seen_failure))
      |> Map.put(:claude?, AgentChat.active?())

    task =
      Task.Supervisor.async_nolink(Agent.task_supervisor(), fn ->
        run_turn(turn, run, content, on_event)
      end)

    %{state | turn: %{task: task, run: run, content: content, claude?: turn.claude?}}
  end

  defp run_turn(turn, run, content, on_event) do
    flow = Flows.get_flow(turn.scope, turn.flow_id)
    latest = flow && latest_execution(flow)
    system = FlowCopilot.system_prompt(flow)

    message =
      FlowCopilot.with_current_state(content, flow, latest, publication: publication(flow))

    read_new_failure(latest, turn.seen_failure, on_event)

    if turn.claude? do
      run_claude(run, system, message, turn.claude, on_event)
    else
      run_llm(turn, run, system, message, on_event)
    end
  end

  defp publication(nil), do: nil

  defp publication(flow) do
    case HeddleCore.Flows.Versions.published_version(flow) do
      nil ->
        :unpublished

      version ->
        if HeddleCore.Flows.Versions.same_graph?(flow, version),
          do: {:published, version.number},
          else: {:changed, version.number}
    end
  end

  # The harness reads a failure itself, and shows it, instead of hoping the model does.
  defp read_new_failure(%{status: "failed", public_id: id} = execution, seen, on_event)
       when id != seen do
    tool = %{id: "failure-#{id}", name: "get_execution"}

    on_event.({:tool_started, Map.put(tool, :args, %{"execution_id" => id})})
    on_event.({:tool_finished, Map.merge(tool, %{ok?: true, output: Jason.encode!(execution)})})
    on_event.({:failure_read, id})
  end

  defp read_new_failure(_execution, _seen, _on_event), do: :ok

  defp run_llm(turn, run, system, content, on_event) do
    # The tools act as the run's key: in the flow's workspace, with the person's role.
    frame = %{assigns: %{api_key: run.api_key, current_scope: Scope.for_api_key(run.api_key)}}

    history = FlowCopilot.without_state(turn.history)

    Harness.run(history ++ [Context.user(content)],
      system: system,
      tools: AgentTools.for_agent(frame),
      on_event: on_event
    )
  end

  defp run_claude(run, system, content, claude, on_event) do
    {:ok, %{stream: stream}} = AgentChat.stream(run, system, content, claude)

    Enum.reduce_while(stream, :claude_done, fn
      {:error, message}, _result ->
        {:halt, {:error, message}}

      event, result ->
        on_event.(event)
        {:cont, result}
    end)
  end

  defp latest_execution(flow) do
    flow
    |> Executions.list_executions_for_flow_page(%{page: 1, per_page: 1})
    |> Map.fetch!(:entries)
    |> List.first()
    |> describe_execution()
  end

  defp describe_execution(nil), do: nil

  defp describe_execution(execution) do
    Map.take(execution, [:public_id, :status, :input, :error, :logs, :inserted_at])
  end

  defp end_turn(state, result) do
    AgentChat.close(state.turn.run)
    if state.scope.user, do: HeddleUI.FlowPresence.untrack_agent(state.flow_id, state.scope.user)

    # The Claude Agent removes its key when its process is gone.
    unless state.turn.claude?, do: ApiKeys.delete_api_key(state.turn.run.api_key)

    state
    |> answer(false)
    |> apply_result(result)
    |> Map.put(:turn, nil)
    |> finish()
  end

  # Saved before anyone hears it is over, or they could look for it and find nothing.
  defp finish(state) do
    event = %{type: "status", status: "idle"}
    state = save(%{state | transcript: Transcript.reduce(state.transcript, event)})

    Agent.broadcast(state.scope.user.id, state.flow_id, event)
    state
  end

  # What the model needs to go on is what was said. It can read the rest again.
  defp history_from(items) do
    Enum.flat_map(items, fn
      %{role: "user", text: text} -> [Context.user(text)]
      %{role: "assistant", text: text} -> [Context.assistant(text)]
      _item -> []
    end)
  end

  defp restart(state, conversation_id, items, history) do
    fresh = %{
      state
      | conversation_id: conversation_id,
        history: history,
        transcript: Transcript.new(),
        runs_allowed?: false,
        seen_failure: nil,
        claude: %{id: Ecto.UUID.generate(), started?: false}
    }

    emit(fresh, %{type: "reset", items: items})
  end

  defp save(state) do
    items = state.transcript.items
    attrs = %{title: title(items), items: items}

    case AgentConversations.save_conversation(
           state.scope,
           state.flow_id,
           state.conversation_id,
           attrs
         ) do
      {:ok, conversation} ->
        %{state | conversation_id: conversation.id}

      {:error, reason} ->
        Logger.warning("Could not save an agent conversation: #{inspect(reason)}")
        state
    end
  end

  defp title(items) do
    case Enum.find(items, &(&1.role == "user")) do
      %{text: text} -> text
      nil -> "Conversation"
    end
  end

  defp apply_result(state, {:ok, history}), do: %{state | history: history}

  defp apply_result(state, :claude_done) do
    put_in(state.claude.started?, true)
  end

  defp apply_result(state, {:stopped, content}) do
    %{state | history: state.history ++ [Context.user(content)]}
  end

  defp apply_result(state, {:error, message}) do
    state = %{state | history: state.history ++ [Context.user(state.turn.content)]}
    emit(state, %{type: "failed", message: message})
  end

  defp answer(%{question: nil} = state, _approved?), do: state

  defp answer(%{question: question} = state, approved?) do
    send(question.reply_to, {:agent_run_decision, question.ref, approved?})

    %{state | question: nil}
    |> emit(%{type: "permission", permission: nil})
  end

  defp to_event({:text_delta, text}), do: %{type: "text_delta", text: text}

  defp to_event({:tool_started, %{id: id, name: name, args: args}}) do
    %{type: "tool_started", id: id, name: name, args: args}
  end

  defp to_event({:tool_finished, %{id: id, ok?: ok?, output: output}}) do
    %{type: "tool_finished", id: id, ok: ok?, output: output}
  end

  defp emit(state, event) do
    Agent.broadcast(state.scope.user.id, state.flow_id, event)
    %{state | transcript: Transcript.reduce(state.transcript, event)}
  end

  defp reply(response, state), do: {:reply, response, state, timeout(state)}
  defp noreply(state), do: {:noreply, state, timeout(state)}

  defp timeout(%{turn: nil}), do: @idle_timeout
  defp timeout(_state), do: :infinity
end
