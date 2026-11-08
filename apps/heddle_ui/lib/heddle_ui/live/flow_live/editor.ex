defmodule HeddleUI.FlowLive.Editor do
  use HeddleUI, :live_view

  require Logger

  alias Heddle.Graph
  alias Heddle.Graph.Layout
  alias HeddleCore.{Credentials, Executions, Flows, Workspaces}
  alias HeddleUI.AIChat
  alias HeddleUI.Agent
  alias HeddleUI.FlowLive.AgentManager
  alias HeddleUI.FlowLive.TerminalManager
  alias HeddleUI.FlowLive.{CodeEditorManager, NodePaletteManager}

  @notice_dismiss_timeout 6_000

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    flow = Flows.get_flow!(socket.assigns.current_scope, id)
    scope = work_in(socket.assigns.current_scope, flow)

    if connected?(socket), do: Flows.subscribe_to_flow(flow.id)

    {:ok,
     socket
     |> assign(:current_scope, scope)
     |> assign(initial_assigns(flow, scope))
     |> AgentManager.follow(), layout: false}
  end

  # A flow opened from another of the person's workspaces makes that one theirs, so
  # going back to the list shows its flows.
  defp work_in(scope, flow) do
    if scope.workspace && scope.workspace.id == flow.workspace_id do
      scope
    else
      workspace = Workspaces.get_workspace(flow.workspace_id)

      case Workspaces.switch_workspace(scope, workspace) do
        {:ok, scope} -> scope
        {:error, _reason} -> scope
      end
    end
  end

  defp initial_assigns(flow, scope) do
    can_edit = Flows.can?(scope, :edit, flow)

    [
      current_flow: flow,
      can_edit: can_edit,
      can_run: Flows.can?(scope, :run, flow),
      has_changes: false,
      renaming_flow: false,
      # Node config drawer
      config_modal_open: false,
      editing_node_data: nil,
      credentials: [],
      current_node_id: nil,
      # Execution result / notice
      execution_result: nil,
      execution_notice: nil,
      show_result_modal: false,
      inspecting_result: false,
      # Testing a webhook
      webhook_test_open: false,
      webhook_test_form: webhook_test_form(%{"method" => "POST", "body" => "{\n  \n}"}),
      webhook_test_error: nil,
      webhook_test_fields: [],
      webhook_test_input: nil,
      # Node error modal
      error_modal_open: false,
      current_error_message: nil,
      current_error_node_id: nil,
      # AI chat: the agent changes the flow, so it is for those who can edit it.
      chat_open: false,
      pending_ai_trigger: false,
      ai_configured: can_edit and Agent.available?()
    ] ++
      AgentManager.initial_assigns() ++
      TerminalManager.initial_assigns(scope.user, can_edit) ++
      CodeEditorManager.initial_assigns() ++
      NodePaletteManager.initial_assigns()
  end

  # Locale & Client Lifecycle
  @impl true
  def handle_event("change_locale", %{"locale" => locale}, socket) do
    {:noreply, redirect(socket, to: ~p"/?locale=#{locale}")}
  end

  @impl true
  def handle_event("client_ready", _params, socket) do
    {:noreply, load_graph(socket, socket.assigns.current_flow)}
  end

  @impl true
  def handle_event("graph_changed", _params, socket) do
    {:noreply, assign(socket, has_changes: true)}
  end

  # Node Palette & Creation (delegated to NodePaletteManager)
  @impl true
  def handle_event("node_added_internally", %{"name" => name}, socket) do
    {:noreply,
     socket
     |> assign(has_changes: true)
     |> NodePaletteManager.record_recent_node(name)}
  end

  @impl true
  def handle_event("clear_recent_nodes", _params, socket) do
    {:noreply, NodePaletteManager.clear_recent_nodes(socket)}
  end

  @impl true
  def handle_event("show_drag_tooltip", %{"name" => name}, socket) do
    {:noreply,
     put_flash(socket, :info, "Drag and drop the '#{name}' node onto the canvas to add it.")}
  end

  @impl true
  def handle_event("add_node", %{"name" => name}, socket) do
    {:noreply, NodePaletteManager.add_node(socket, name)}
  end

  @impl true
  def handle_event("open_create_node_modal", params, socket) do
    {:noreply, NodePaletteManager.open_create_modal(socket, params)}
  end

  @impl true
  def handle_event("close_create_node_modal", _params, socket) do
    {:noreply, NodePaletteManager.close_create_modal(socket)}
  end

  @impl true
  def handle_event("create_node_from_modal", %{"name" => name}, socket) do
    {:noreply, NodePaletteManager.create_node_from_modal(socket, name)}
  end

  @impl true
  def handle_event("filter_nodes", %{"value" => query}, socket) do
    {:noreply, NodePaletteManager.filter_modal_nodes(socket, query)}
  end

  @impl true
  def handle_event("filter_sidebar_nodes", %{"node_search" => %{"query" => query}}, socket) do
    {:noreply, NodePaletteManager.filter_sidebar_nodes(socket, query)}
  end

  @impl true
  def handle_event("toggle_node_category", %{"category" => category}, socket) do
    {:noreply, NodePaletteManager.toggle_category(socket, category)}
  end

  # Code Editor Modal (delegated to CodeEditorManager)
  @impl true
  def handle_event("open_code_editor", params, socket) do
    {:noreply, CodeEditorManager.open_from_event(socket, params)}
  end

  @impl true
  def handle_event("open_code_editor_from_config", params, socket) do
    {:noreply, CodeEditorManager.open_from_config(socket, params)}
  end

  @impl true
  def handle_event("switch_language", %{"lang" => lang}, socket) do
    {:noreply, CodeEditorManager.switch_language(socket, lang)}
  end

  @impl true
  def handle_event("switch_code_tab", %{"tab" => tab}, socket) do
    {:noreply, CodeEditorManager.switch_tab(socket, tab)}
  end

  @impl true
  def handle_event("close_modal", _params, socket) do
    {:noreply, CodeEditorManager.close(socket)}
  end

  @impl true
  def handle_event("save_code", params, socket) do
    {:noreply, CodeEditorManager.save(socket, params)}
  end

  # Node Configuration Drawer
  @impl true
  def handle_event("open_node_config", %{"nodeData" => node_data}, socket) do
    {:noreply,
     assign(socket,
       config_modal_open: true,
       editing_node_data: node_data,
       credentials: Credentials.list_credentials(socket.assigns.current_scope),
       current_node_id: node_data["id"]
     )}
  end

  @impl true
  def handle_event("node_config_changed", params, socket) do
    {:noreply, update(socket, :editing_node_data, &put_control_values(&1, params))}
  end

  @impl true
  def handle_event("close_config_modal", _params, socket) do
    {:noreply,
     assign(socket, config_modal_open: false, editing_node_data: nil, current_node_id: nil)}
  end

  @impl true
  def handle_event("handle_keydown", %{"key" => "Escape"}, socket) do
    {:noreply,
     assign(socket, config_modal_open: false, editing_node_data: nil, current_node_id: nil)}
  end

  @impl true
  def handle_event("handle_keydown", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("save_node_config", _params, %{assigns: %{can_edit: false}} = socket) do
    {:noreply, read_only(socket)}
  end

  def handle_event("save_node_config", params, socket) do
    node_id = socket.assigns.current_node_id
    config_data = Map.drop(params, ["_csrf_token", "_target", "node_label"])
    node_label = params["node_label"]

    socket =
      if node_label && node_label != socket.assigns.editing_node_data["label"] do
        push_event(socket, "update_node_label", %{nodeId: node_id, label: node_label})
      else
        socket
      end

    socket = sync_node_sockets(socket, node_id, config_data)

    socket =
      socket
      |> push_event("update_node_data", %{nodeId: node_id, data: config_data})
      |> assign(
        config_modal_open: false,
        editing_node_data: nil,
        current_node_id: nil,
        inspecting_result: false
      )

    {:noreply, socket}
  end

  # Flow Saving & Renaming
  @impl true
  def handle_event("edit_flow_name", _params, socket) do
    {:noreply, assign(socket, renaming_flow: socket.assigns.can_edit)}
  end

  @impl true
  def handle_event("cancel_rename_flow", _params, socket) do
    {:noreply, assign(socket, renaming_flow: false)}
  end

  @impl true
  def handle_event("save_flow_name", %{"name" => new_name}, socket) do
    if String.trim(new_name) != "" do
      case Flows.update_flow(socket.assigns.current_scope, socket.assigns.current_flow, %{
             name: new_name
           }) do
        {:ok, updated_flow} ->
          {:noreply, assign(socket, current_flow: updated_flow, renaming_flow: false)}

        {:error, :forbidden} ->
          {:noreply, socket |> assign(renaming_flow: false) |> read_only()}

        {:error, _} ->
          {:noreply,
           assign(socket, renaming_flow: false) |> put_flash(:error, "Failed to rename flow")}
      end
    else
      {:noreply, assign(socket, renaming_flow: false)}
    end
  end

  @impl true
  def handle_event("save_graph", _params, socket) do
    {:noreply, push_event(socket, "request_graph_data", %{})}
  end

  @impl true
  def handle_event("save_graph_data", %{"data" => data}, socket) do
    case Flows.update_flow(socket.assigns.current_scope, socket.assigns.current_flow, data) do
      {:ok, updated_flow} ->
        {:noreply,
         socket
         |> assign(current_flow: updated_flow, has_changes: false)
         |> AgentManager.resume_pending()}

      {:error, :forbidden} ->
        {:noreply, socket |> AgentManager.abort_pending() |> read_only()}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> AgentManager.abort_pending()
         |> put_flash(:error, gettext("Failed to save graph data."))}
    end
  end

  # Flow Execution & Run
  @impl true
  def handle_event("run_flow", _params, socket) do
    {:noreply, push_event(socket, "request_save_and_run", %{})}
  end

  @impl true
  def handle_event("save_and_run", %{"data" => data}, socket) do
    if socket.assigns.webhook_test_input == nil and starts_at_webhook?(data) do
      {:noreply,
       assign(socket,
         webhook_test_open: true,
         webhook_test_error: nil,
         webhook_test_fields:
           Graph.body_fields(Graph.new(%{nodes: data["nodes"], connections: []}))
       )}
    else
      {:noreply, save_and_run(socket, data)}
    end
  end

  @impl true
  def handle_event("close_webhook_test", _params, socket) do
    {:noreply, assign(socket, webhook_test_open: false)}
  end

  @impl true
  def handle_event("run_webhook_test", %{"webhook_test" => params}, socket) do
    socket = assign(socket, webhook_test_form: webhook_test_form(params))

    case decode_body(params["body"]) do
      {:ok, body} ->
        input = Executions.webhook_input(%{"method" => params["method"], "body" => body})

        {:noreply,
         socket
         |> assign(webhook_test_open: false, webhook_test_input: input)
         |> push_event("request_save_and_run", %{})}

      :error ->
        {:noreply, assign(socket, webhook_test_error: gettext("The body isn't valid JSON."))}
    end
  end

  @impl true
  def handle_event("close_result_modal", _params, socket) do
    {:noreply, assign(socket, show_result_modal: false, inspecting_result: false)}
  end

  @impl true
  def handle_event("dismiss_execution_notice", _params, socket) do
    {:noreply, assign(socket, execution_notice: nil)}
  end

  @impl true
  def handle_event("open_execution_result", %{"id" => execution_id}, socket) do
    case Executions.get_execution(socket.assigns.current_scope, execution_id) do
      nil -> {:noreply, socket}
      execution -> {:noreply, show_execution_result(socket, execution)}
    end
  end

  @impl true
  def handle_event("toggle_inspect_result", _params, socket) do
    {:noreply, assign(socket, inspecting_result: !socket.assigns.inspecting_result)}
  end

  # Error Details Modal
  @impl true
  def handle_event("show_error_details", %{"nodeId" => node_id, "message" => message}, socket) do
    {:noreply,
     assign(socket,
       error_modal_open: true,
       current_error_node_id: node_id,
       current_error_message: message
     )}
  end

  @impl true
  def handle_event("close_error_modal", _params, socket) do
    {:noreply,
     assign(socket,
       error_modal_open: false,
       current_error_node_id: nil,
       current_error_message: nil
     )}
  end

  # Dynamic Node / AST queries
  @impl true
  def handle_event("get_node_definition", %{"name" => name}, socket) do
    {:reply, %{definition: HeddleNodes.Nodes.get_node(name)}, socket}
  end

  @impl true
  def handle_event("parse_node_ui", %{"code" => code}, socket) do
    {:ok, ui_fields} = HeddleUI.CodeParser.parse_ui_definition(code)
    {:reply, %{ui_fields: ui_fields}, socket}
  end

  # AI Chat & Assistants
  @impl true
  def handle_event("toggle_chat", _params, socket) do
    {:noreply, assign(socket, chat_open: !socket.assigns.chat_open)}
  end

  @impl true
  def handle_event("send_message", %{"content" => content}, socket) do
    case String.trim(content) do
      "" -> {:noreply, socket}
      content -> {:noreply, AgentManager.send_message(socket, content)}
    end
  end

  @impl true
  def handle_event("agent_run_decision", %{"decision" => decision}, socket) do
    {:noreply, AgentManager.decide(socket, decision)}
  end

  @impl true
  def handle_event("terminal_toggle", _params, socket) do
    {:noreply, TerminalManager.toggle(socket)}
  end

  @impl true
  def handle_event("terminal_exited", _params, socket) do
    {:noreply, TerminalManager.exited(socket)}
  end

  @impl true
  def handle_event("terminal_restart", _params, socket) do
    {:noreply, TerminalManager.restart(socket)}
  end

  @impl true
  def handle_event("agent_stop", _params, socket) do
    {:noreply, AgentManager.stop(socket)}
  end

  @impl true
  def handle_event("agent_new_chat", _params, socket) do
    {:noreply, AgentManager.new_conversation(socket)}
  end

  @impl true
  def handle_event("agent_toggle_history", _params, socket) do
    {:noreply, AgentManager.toggle_history(socket)}
  end

  @impl true
  def handle_event("agent_open_conversation", %{"id" => id}, socket) do
    {:noreply, AgentManager.open_conversation(socket, id)}
  end

  # Process Messages (info)
  @impl true
  def handle_info({:dismiss_execution_notice, execution_id, dismiss_ref}, socket) do
    notice = socket.assigns.execution_notice

    socket =
      if notice && notice.execution_id == execution_id && notice.dismiss_ref == dismiss_ref do
        assign(socket, execution_notice: nil)
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:dismiss_execution_notice, execution_id}, socket) do
    notice = socket.assigns.execution_notice

    socket =
      if notice && notice.execution_id == execution_id && notice.status == "queued" do
        assign(socket, execution_notice: nil)
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:execution_updated, execution}, socket) do
    {:noreply, assign(socket, execution_notice: execution_notice(execution.status, execution))}
  end

  @impl true
  def handle_info({:agent_event, event}, socket) do
    {:noreply, AgentManager.apply_event(socket, event)}
  end

  @impl true
  def handle_info({:flow_updated, flow}, socket) do
    if same_graph?(flow, socket.assigns.current_flow) do
      {:noreply, assign(socket, current_flow: flow)}
    else
      {:noreply,
       socket
       |> assign(current_flow: flow, has_changes: false)
       |> load_graph(flow)}
    end
  end

  attr :kind, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true

  defp canvas_tool(assigns) do
    ~H"""
    <button
      id={"add-comment-#{@kind}"}
      type="button"
      data-comment-kind={@kind}
      class="flex items-center gap-1.5 rounded-md px-2.5 py-1.5 text-sm font-medium text-gray-700 transition hover:bg-gray-100 hover:text-primary dark:text-slate-200 dark:hover:bg-slate-700 dark:hover:text-primary"
    >
      <.icon name={@icon} class="size-4" />
      {@label}
    </button>
    """
  end

  # Private Helpers
  defp load_graph(socket, flow) do
    push_event(socket, "load_graph_data", %{
      nodes: Layout.place(flow.nodes, flow.connections),
      connections: Graph.normalize_connections(flow.connections),
      comments: flow.comments,
      definitions: AIChat.node_definitions()
    })
  end

  # The editor hears its own saves too, and those must not reload the canvas.
  defp same_graph?(flow, current) do
    flow.nodes == current.nodes and flow.connections == current.connections and
      flow.comments == current.comments
  end

  # Keeps what is typed in the drawer, which redraws when a control changes.
  defp put_control_values(%{"controls" => controls} = node_data, params) do
    params = forget_model(controls, params)

    controls =
      Map.new(controls, fn {key, control} ->
        {key, Map.put(control, "value", Map.get(params, key, control["value"]))}
      end)

    %{node_data | "controls" => controls}
    |> Map.put("label", params["node_label"] || node_data["label"])
  end

  defp put_control_values(node_data, _params), do: node_data

  # A model belongs to a provider, so it doesn't survive a change of credential.
  defp forget_model(%{"model" => %{"type" => "model"}} = controls, params) do
    credential = get_in(controls, ["credential", "value"])

    if Map.get(params, "credential", credential) == credential do
      params
    else
      Map.put(params, "model", "")
    end
  end

  defp forget_model(_controls, params), do: params

  defp sync_node_sockets(socket, node_id, config_data) do
    Enum.reduce(config_data, socket, fn {_key, value}, acc_socket ->
      if String.starts_with?(value, "ui do") do
        {:ok, ui_fields} = HeddleUI.CodeParser.parse_ui_definition(value)
        inputs = Enum.filter(ui_fields, &(&1.type == "input")) |> Enum.map(& &1.name)
        outputs = Enum.filter(ui_fields, &(&1.type == "output")) |> Enum.map(& &1.name)

        if inputs != [] or outputs != [] do
          push_event(acc_socket, "update_node_sockets", %{
            nodeId: node_id,
            inputs: inputs,
            outputs: outputs
          })
        else
          acc_socket
        end
      else
        acc_socket
      end
    end)
  end

  defp subscribe_to_execution(socket, execution) do
    if connected?(socket), do: Executions.subscribe_to_execution(execution)
    socket
  end

  defp schedule_execution_notice_dismiss(socket, execution_id) do
    dismiss_ref = System.unique_integer([:positive])
    notice = socket.assigns.execution_notice

    Process.send_after(
      self(),
      {:dismiss_execution_notice, execution_id, dismiss_ref},
      @notice_dismiss_timeout
    )

    if notice && notice.execution_id == execution_id do
      assign(socket, execution_notice: Map.put(notice, :dismiss_ref, dismiss_ref))
    else
      socket
    end
  end

  defp show_execution_result(socket, execution) do
    assign(socket,
      execution_notice: nil,
      execution_result: execution_modal_result(execution),
      show_result_modal: true,
      inspecting_result: false
    )
  end

  defp read_only(socket) do
    put_flash(
      socket,
      :error,
      gettext("Your role in this workspace lets you see this flow, not change it.")
    )
  end

  # An operator runs the flow as it was saved: they can't change it.
  defp save_and_run(%{assigns: %{can_edit: false, can_run: true}} = socket, _data) do
    %{current_scope: scope, current_flow: flow, webhook_test_input: input} = socket.assigns
    socket = assign(socket, webhook_test_input: nil)

    case Executions.run(scope, flow, input || %{"trigger" => "manual"}) do
      {:ok, execution} ->
        socket
        |> assign(
          execution_result: nil,
          execution_notice: execution_notice(:queued, execution),
          show_result_modal: false,
          inspecting_result: false
        )
        |> subscribe_to_execution(execution)
        |> schedule_execution_notice_dismiss(execution.id)
        |> push_event("clear_node_errors", %{})

      {:error, _reason} ->
        put_flash(socket, :error, gettext("The flow could not be started."))
    end
  end

  defp save_and_run(%{assigns: %{can_run: false}} = socket, _data) do
    put_flash(socket, :error, gettext("Your role in this workspace can't run flows."))
  end

  defp save_and_run(socket, data) do
    %{current_scope: scope, current_flow: flow, webhook_test_input: input} = socket.assigns
    socket = assign(socket, webhook_test_input: nil)

    case Executions.save_and_run(scope, flow, data, input || %{"trigger" => "manual"}) do
      {:ok, %{flow: updated_flow, execution: execution}} ->
        socket
        |> assign(
          current_flow: updated_flow,
          has_changes: false,
          execution_result: nil,
          execution_notice: execution_notice(:queued, execution),
          show_result_modal: false,
          inspecting_result: false
        )
        |> subscribe_to_execution(execution)
        |> schedule_execution_notice_dismiss(execution.id)
        |> put_flash(:info, "Flow saved and execution queued.")
        |> push_event("clear_node_errors", %{})

      {:error, stage, context} ->
        handle_run_failure(socket, stage, context)
    end
  end

  # With a Start, a person can run the flow as it is. A Webhook needs a request.
  defp starts_at_webhook?(%{"nodes" => nodes}) do
    graph = Graph.new(%{nodes: nodes, connections: []})

    Graph.of_type(graph, "Webhook") != [] and Graph.of_type(graph, "Start") == []
  end

  defp starts_at_webhook?(_data), do: false

  defp webhook_test_form(params), do: to_form(params, as: :webhook_test)

  defp decode_body(body) do
    case String.trim(body || "") do
      "" -> {:ok, %{}}
      json -> with {:error, _reason} <- Jason.decode(json), do: :error
    end
  end

  defp handle_run_failure(socket, stage, context) do
    socket =
      case context do
        %{flow: flow} -> assign(socket, current_flow: flow, has_changes: false)
        _ -> socket
      end

    socket
    |> assign(execution_notice: run_failure_notice(stage, context))
    |> put_flash(:error, run_failure_flash(stage))
  end

  defp run_failure_notice(:enqueue, %{execution: execution}) do
    %{
      kind: :error,
      status: "failed",
      title: "Execution was not queued",
      message: "The flow was saved, but the execution job could not be created.",
      execution_id: execution.id,
      public_id: execution.public_id
    }
  end

  defp run_failure_notice(:create, _context) do
    %{
      kind: :error,
      status: "failed",
      title: "Execution was not created",
      message: "The flow was saved, but the execution record could not be created.",
      execution_id: nil
    }
  end

  defp run_failure_notice(:save, _context) do
    %{
      kind: :error,
      status: "failed",
      title: "Flow was not saved",
      message: "The execution was not queued because the graph could not be saved.",
      execution_id: nil
    }
  end

  defp run_failure_flash(:enqueue), do: "Flow saved, but execution could not be queued."
  defp run_failure_flash(:create), do: "Flow saved, but execution could not be created."
  defp run_failure_flash(:save), do: "Failed to save flow before running."

  defp execution_notice(:queued, execution) do
    %{
      kind: :info,
      status: "queued",
      title: "Execution queued",
      message: "The flow was saved and is waiting for the worker to run.",
      execution_id: execution.id,
      public_id: execution.public_id,
      dismiss_ref: nil
    }
  end

  defp execution_notice("succeeded", execution) do
    %{
      kind: :success,
      status: "succeeded",
      title: "Execution finished",
      message: "The flow run is ready to inspect.",
      execution_id: execution.id,
      public_id: execution.public_id,
      dismiss_ref: nil
    }
  end

  defp execution_notice("failed", execution) do
    %{
      kind: :error,
      status: "failed",
      title: "Execution failed",
      message: "The flow run finished with an error. Open it to inspect the details.",
      execution_id: execution.id,
      public_id: execution.public_id,
      dismiss_ref: nil
    }
  end

  defp execution_notice(_status, execution) do
    %{
      kind: :info,
      status: "running",
      title: "Execution running",
      message: "The worker is processing this flow run.",
      execution_id: execution.id,
      public_id: execution.public_id,
      dismiss_ref: nil
    }
  end

  defp execution_modal_result(execution) do
    %{
      "execution_id" => execution.id,
      "public_id" => execution.public_id,
      "status" => execution.status,
      "result" => execution.result,
      "error" => execution.error,
      "logs" => execution.logs
    }
  end
end
