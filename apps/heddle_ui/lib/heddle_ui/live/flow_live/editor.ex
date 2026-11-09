defmodule HeddleUI.FlowLive.Editor do
  use HeddleUI, :live_view

  require Logger

  alias Heddle.Graph
  alias HeddleCore.{Credentials, Executions, Flows, Workspaces}
  alias HeddleUI.Agent
  alias HeddleUI.FlowLive.AgentManager
  alias HeddleUI.FlowLive.TerminalManager
  alias HeddleUI.FlowLive.{CodeEditorManager, InspectorManager, NodePaletteManager, NodeSettings}
  alias HeddleUI.FlowLive.FormManager
  alias HeddleUI.FlowLive.VersionsManager

  @impl true
  def mount(%{"id" => id} = params, _session, socket) do
    flow = Flows.get_flow!(socket.assigns.current_scope, id)
    scope = work_in(socket.assigns.current_scope, flow)

    if connected?(socket) do
      Flows.subscribe_to_flow(flow.id)
      HeddleCore.Flows.Session.subscribe(flow.id)
    end

    {:ok,
     socket
     |> assign(:current_scope, scope)
     |> assign(initial_assigns(flow, scope))
     # `?execution=` opens the inspector on that run once the canvas is there.
     |> assign(inspect_on_load: params["execution"])
     |> VersionsManager.mount()
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
      # The canvas edits the flow through a socket of its own, see `HeddleUI.FlowSocket`.
      flow_socket_token: HeddleUI.FlowSocket.token(scope.user),
      renaming_flow: false,
      # Node config drawer
      config_modal_open: false,
      editing_node_data: nil,
      credentials: [],
      # The flows a Subflow node can run: the others of the workspace.
      subflow_options: [],
      current_node_id: nil,
      # Execution notice
      execution_notice: nil,
      # Testing a webhook
      webhook_test_open: false,
      webhook_test_form: webhook_test_form(%{"method" => "POST", "body" => "{\n  \n}"}),
      webhook_test_error: nil,
      webhook_test_fields: [],
      # The input of the next run, when it isn't a plain manual run: a webhook test,
      # or a run the inspector starts again
      next_run_input: nil,
      # The section a run takes alone, see `Heddle.Graph.Section`
      run_section_id: nil,
      # Flow settings
      flow_settings_open: false,
      flow_settings_form: flow_settings_form(flow),
      error_flow_options: [],
      # AI chat: the agent changes the flow, so it is for those who can edit it.
      chat_open: false,
      pending_ai_trigger: false,
      ai_configured: can_edit and Agent.available?()
    ] ++
      AgentManager.initial_assigns() ++
      InspectorManager.initial_assigns() ++
      TerminalManager.initial_assigns(scope.user, can_edit) ++
      CodeEditorManager.initial_assigns() ++
      NodePaletteManager.initial_assigns() ++
      VersionsManager.initial_assigns(flow) ++
      FormManager.initial_assigns() ++
      [publish_note: nil]
  end

  # Client Lifecycle
  @impl true
  # The canvas gets the flow from its own channel, see `HeddleUI.FlowChannel`.
  def handle_event("client_ready", _params, socket) do
    {:noreply, inspect_on_load(socket)}
  end

  @impl true
  def handle_event("canvas_join_failed", _params, socket) do
    {:noreply, put_flash(socket, :error, gettext("The canvas couldn't connect to this flow."))}
  end

  # Node Palette & Creation (delegated to NodePaletteManager)
  @impl true
  def handle_event("node_added_internally", %{"name" => name}, socket) do
    {:noreply, NodePaletteManager.record_recent_node(socket, name)}
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
  def handle_event("load_their_code", _params, socket) do
    {:noreply, CodeEditorManager.load_theirs(socket)}
  end

  @impl true
  def handle_event("save_code", params, socket) do
    {:noreply, CodeEditorManager.save(socket, params)}
  end

  # Node Configuration Drawer
  @impl true
  def handle_event("open_node_config", %{"nodeData" => node_data}, socket) do
    {:noreply,
     socket
     |> assign(
       config_modal_open: true,
       editing_node_data: node_data,
       credentials: Credentials.list_credentials(socket.assigns.current_scope),
       subflow_options: subflow_options(socket, node_data),
       current_node_id: node_data["id"]
     )
     |> FormManager.opened(node_data)}
  end

  @impl true
  # Each field reaches the canvas as it changes, and from there everyone editing the
  # flow: there is nothing to save.
  def handle_event("node_config_changed", params, socket) do
    params = FormManager.encode_fields(socket.assigns.editing_node_data, params)

    socket =
      update(socket, :editing_node_data, fn node_data ->
        node_data |> put_control_values(params) |> put_settings_values(params["settings"])
      end)

    {:noreply, if(socket.assigns.can_edit, do: push_node_changes(socket, params), else: socket)}
  end

  # A Form Trigger's fields and link, see `HeddleUI.FlowLive.FormManager`.
  @impl true
  def handle_event("form_field_add", _params, socket) do
    {:noreply, FormManager.add_field(socket)}
  end

  @impl true
  def handle_event("form_field_remove", %{"index" => index}, socket) do
    {:noreply, FormManager.remove_field(socket, String.to_integer(index))}
  end

  @impl true
  def handle_event("form_field_move", %{"index" => index, "direction" => direction}, socket) do
    {:noreply, FormManager.move_field(socket, String.to_integer(index), direction)}
  end

  @impl true
  def handle_event("form_regenerate_link", _params, socket) do
    {:noreply, FormManager.regenerate(socket)}
  end

  @impl true
  def handle_event("form_create_table", _params, socket) do
    {:noreply, FormManager.create_table(socket)}
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
  def handle_event("unpin_node", _params, %{assigns: %{can_edit: false}} = socket) do
    {:noreply, read_only(socket)}
  end

  def handle_event("unpin_node", _params, %{assigns: %{editing_node_data: %{} = node}} = socket) do
    settings = Map.delete(node["settings"] || %{}, "pin")

    {:noreply,
     socket
     |> assign(
       :editing_node_data,
       node |> Map.put("settings", settings) |> Map.delete("pin_invalid")
     )
     |> push_event("update_node_settings", %{nodeId: node["id"], settings: settings})}
  end

  def handle_event("unpin_node", _params, socket), do: {:noreply, socket}

  # Flow Settings
  @impl true
  def handle_event("open_flow_settings", _params, %{assigns: %{can_edit: false}} = socket) do
    {:noreply, read_only(socket)}
  end

  @impl true
  def handle_event("open_flow_settings", _params, socket) do
    %{current_scope: scope, current_flow: flow} = socket.assigns

    options =
      for other <- Flows.list_flows(scope), other.id != flow.id, do: {other.name, other.id}

    {:noreply,
     assign(socket,
       flow_settings_open: true,
       flow_settings_form: flow_settings_form(flow),
       error_flow_options: options
     )}
  end

  @impl true
  def handle_event("close_flow_settings", _params, socket) do
    {:noreply, assign(socket, flow_settings_open: false)}
  end

  @impl true
  def handle_event("save_flow_settings", %{"flow_settings" => params}, socket) do
    %{current_scope: scope, current_flow: flow} = socket.assigns

    case Flows.update_flow_settings(scope, flow, params) do
      {:ok, flow} ->
        {:noreply,
         socket
         |> assign(current_flow: flow, flow_settings_open: false)
         |> put_flash(:info, gettext("Flow settings saved."))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Those settings couldn't be saved."))}
    end
  end

  # Run Inspector (delegated to InspectorManager)
  @impl true
  def handle_event("inspector_select", %{"index" => index}, socket) do
    {:noreply, InspectorManager.select(socket, InspectorManager.parse_index(index))}
  end

  @impl true
  def handle_event("inspector_select_node", %{"node_id" => node_id}, socket) do
    {:noreply, InspectorManager.select_node(socket, node_id)}
  end

  @impl true
  def handle_event("inspector_tab", %{"tab" => tab}, socket) do
    {:noreply, InspectorManager.tab(socket, tab)}
  end

  @impl true
  def handle_event("inspector_toggle", _params, socket) do
    {:noreply, InspectorManager.toggle(socket)}
  end

  @impl true
  def handle_event("inspector_close", _params, socket) do
    {:noreply, InspectorManager.close(socket)}
  end

  @impl true
  def handle_event("inspector_focus", _params, socket) do
    {:noreply, InspectorManager.focus_node(socket)}
  end

  @impl true
  def handle_event("inspector_rerun", _params, socket) do
    case InspectorManager.rerun_input(socket) do
      {:ok, input} -> {:noreply, run_with(socket, input)}
      :error -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("inspector_replay", %{"index" => index}, socket) do
    case InspectorManager.replay_input(socket, InspectorManager.parse_index(index)) do
      {:ok, input} ->
        {:noreply, run_with(socket, input)}

      {:error, :incomplete} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Only part of what this step got was kept, so it can't run again from here.")
         )}

      {:error, :not_found} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("inspector_pin", _params, %{assigns: %{can_edit: false}} = socket) do
    {:noreply, read_only(socket)}
  end

  @impl true
  def handle_event("inspector_unpin", _params, %{assigns: %{can_edit: false}} = socket) do
    {:noreply, read_only(socket)}
  end

  @impl true
  def handle_event("inspector_pin", %{"index" => index}, socket) do
    case InspectorManager.pin(socket, InspectorManager.parse_index(index)) do
      {:ok, socket} ->
        {:noreply,
         put_flash(
           socket,
           :info,
           gettext("Output pinned. Runs from the editor take it instead of running the node.")
         )}

      :error ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("inspector_unpin", %{"node" => node_id}, socket) do
    {:noreply, InspectorManager.unpin(socket, node_id)}
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

  # Versions & publishing (delegated to VersionsManager)
  @impl true
  def handle_event("versions_toggle", _params, socket) do
    {:noreply, VersionsManager.toggle(socket)}
  end

  @impl true
  def handle_event("version_preview", %{"id" => id}, socket) do
    {:noreply, VersionsManager.preview(socket, id)}
  end

  @impl true
  def handle_event("version_preview_ready", _params, socket) do
    {:reply, VersionsManager.preview_graph(socket.assigns) || %{}, socket}
  end

  @impl true
  def handle_event("version_preview_close", _params, socket) do
    {:noreply, VersionsManager.close_preview(socket)}
  end

  @impl true
  def handle_event(event, _params, %{assigns: %{can_edit: false}} = socket)
      when event in ~w(version_restore version_publish open_publish publish publish_graph_data) do
    {:noreply, read_only(socket)}
  end

  @impl true
  def handle_event("version_restore", %{"id" => id}, socket) do
    {:noreply, VersionsManager.restore(socket, id)}
  end

  @impl true
  def handle_event("version_publish", %{"id" => id}, socket) do
    {:noreply, VersionsManager.publish_version(socket, id)}
  end

  @impl true
  def handle_event("open_publish", _params, socket) do
    {:noreply, VersionsManager.open_publish(socket)}
  end

  @impl true
  def handle_event("close_publish", _params, socket) do
    {:noreply, VersionsManager.close_publish(socket)}
  end

  # What is published is what the canvas has, saved or not, so it asks for it first.
  @impl true
  def handle_event("publish", %{"publish" => params}, socket) do
    {:noreply,
     socket
     |> assign(publish_note: params["note"])
     |> push_event("request_publish_data", %{})}
  end

  @impl true
  def handle_event("publish_graph_data", _params, socket) do
    note = socket.assigns.publish_note

    {:noreply,
     socket
     |> assign(publish_note: nil)
     |> VersionsManager.publish(%{"note" => note})}
  end

  # Importing replaces the draft, for everyone editing it: the browser asks first when
  # there is a flow on the canvas. The draft it had is kept as a version.
  @impl true
  def handle_event("import_flow", %{"json" => json}, socket) when is_binary(json) do
    case Flows.import_into(socket.assigns.current_scope, socket.assigns.current_flow, json) do
      {:ok, flow} ->
        {:noreply,
         socket
         |> assign(current_flow: flow)
         |> put_flash(:info, gettext("Flow imported."))}

      {:error, :forbidden} ->
        {:noreply, read_only(socket)}

      {:error, %Ecto.Changeset{}} ->
        {:noreply, put_flash(socket, :error, gettext("That flow can't be imported here."))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, import_error(reason))}
    end
  end

  @impl true
  def handle_event("import_flow_too_big", _params, socket) do
    {:noreply, put_flash(socket, :error, import_error(:too_big))}
  end

  # Flow Execution & Run
  @impl true
  def handle_event("run_flow", _params, socket) do
    {:noreply,
     socket
     |> assign(run_section_id: nil)
     |> push_event("request_save_and_run", %{})}
  end

  @impl true
  def handle_event("run_section", %{"section_id" => id, "data" => data}, socket) do
    {:noreply, socket |> assign(run_section_id: id) |> run_or_ask(data)}
  end

  @impl true
  def handle_event("save_and_run", %{"data" => data}, socket) do
    {:noreply, run_or_ask(socket, data)}
  end

  @impl true
  def handle_event("close_webhook_test", _params, socket) do
    {:noreply, assign(socket, webhook_test_open: false, run_section_id: nil)}
  end

  @impl true
  def handle_event("run_webhook_test", %{"webhook_test" => params}, socket) do
    socket = assign(socket, webhook_test_form: webhook_test_form(params))

    case decode_body(params["body"]) do
      {:ok, body} ->
        input = Executions.webhook_input(%{"method" => params["method"], "body" => body})

        {:noreply,
         socket
         |> assign(webhook_test_open: false, next_run_input: input)
         |> push_event("request_save_and_run", %{})}

      :error ->
        {:noreply, assign(socket, webhook_test_error: gettext("The body isn't valid JSON."))}
    end
  end

  @impl true
  def handle_event("dismiss_execution_notice", _params, socket) do
    {:noreply, assign(socket, execution_notice: nil)}
  end

  @impl true
  def handle_event("open_execution_result", %{"id" => execution_id}, socket) do
    case Executions.get_execution(socket.assigns.current_scope, execution_id) do
      %{flow_id: flow_id} = execution when flow_id == socket.assigns.current_flow.id ->
        {:noreply, socket |> assign(execution_notice: nil) |> InspectorManager.open(execution)}

      _other ->
        {:noreply, socket}
    end
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
    if InspectorManager.showing?(socket, execution.id) do
      {:noreply, InspectorManager.updated(socket, execution)}
    else
      {:noreply, assign(socket, execution_notice: execution_notice(execution.status, execution))}
    end
  end

  @impl true
  def handle_info({:execution_step, execution_id, entry}, socket) do
    {:noreply, InspectorManager.step(socket, execution_id, entry)}
  end

  @impl true
  def handle_info(:inspector_flush, socket) do
    {:noreply, InspectorManager.flush(socket)}
  end

  @impl true
  def handle_info({:agent_event, event}, socket) do
    {:noreply, AgentManager.apply_event(socket, event)}
  end

  @impl true
  # The canvas follows the draft through its channel. This keeps the rest: the name,
  # the settings and what is published.
  def handle_info({:flow_updated, flow}, socket) do
    {:noreply, socket |> assign(current_flow: flow) |> VersionsManager.refresh()}
  end

  @impl true
  def handle_info({:flow_ops, change}, socket) do
    {:noreply, follow_node(socket, change)}
  end

  @impl true
  def handle_info({:flow_versions_changed, _flow_id}, socket) do
    {:noreply, VersionsManager.refresh(socket)}
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

  # What the drawer shows changes on the canvas as it is typed: there is nothing to
  # save. Settings go once they are valid, pinned data once it is a JSON object.
  defp push_node_changes(socket, params) do
    node_id = socket.assigns.current_node_id
    config_data = Map.drop(params, ["_csrf_token", "_target", "node_label", "settings"])
    label = params["node_label"]

    socket =
      if is_binary(label) and label != "",
        do: push_event(socket, "update_node_label", %{nodeId: node_id, label: label}),
        else: socket

    socket =
      socket
      |> sync_node_sockets(node_id, config_data)
      |> push_event("update_node_data", %{nodeId: node_id, data: config_data})

    settings = params["settings"]

    case is_map(settings) and NodeSettings.from_params(settings) do
      {:ok, settings} ->
        push_event(socket, "update_node_settings", %{nodeId: node_id, settings: settings})

      _none ->
        socket
    end
  end

  # Someone else changed the node open in the drawer: the fields follow, and the one
  # being typed in keeps what is typed, since the page doesn't touch a focused field.
  defp follow_node(%{assigns: %{config_modal_open: true, current_node_id: id}} = socket, change)
       when is_binary(id) do
    if change.user_id == socket.assigns.current_scope.user.id do
      socket
    else
      Enum.reduce(change.ops, socket, &follow_op(&2, &1, id))
    end
  end

  defp follow_node(socket, _change), do: socket

  defp follow_op(socket, %{"op" => "remove_node", "id" => id}, id) do
    socket
    |> assign(config_modal_open: false, editing_node_data: nil, current_node_id: nil)
    |> put_flash(:info, gettext("Someone else removed the node you had open."))
  end

  defp follow_op(socket, %{"op" => "update_node", "id" => id, "set" => set}, id) do
    update(socket, :editing_node_data, fn
      nil -> nil
      node_data -> merge_node(node_data, set)
    end)
  end

  defp follow_op(socket, _op, _id), do: socket

  defp merge_node(node_data, set) do
    Enum.reduce(set, node_data, fn
      {"controls", controls}, acc when is_map(controls) ->
        Enum.reduce(controls, acc, fn {key, value}, acc ->
          if get_in(acc, ["controls", key]),
            do: put_in(acc, ["controls", key, "value"], value),
            else: acc
        end)

      {"label", label}, acc ->
        Map.put(acc, "label", label)

      {"settings", settings}, acc ->
        Map.put(acc, "settings", settings || %{})

      _other, acc ->
        acc
    end)
  end

  # Pinned data that isn't a JSON object yet stays as typed, and the drawer says so.
  defp put_settings_values(node_data, params) when is_map(params) do
    case NodeSettings.from_params(params) do
      {:ok, settings} ->
        node_data |> Map.put("settings", settings) |> Map.delete("pin_invalid")

      {:error, :invalid_pin} ->
        Map.put(node_data, "pin_invalid", true)
    end
  end

  defp put_settings_values(node_data, _params), do: node_data

  defp inspect_on_load(%{assigns: %{inspect_on_load: public_id}} = socket)
       when is_binary(public_id) do
    socket = assign(socket, inspect_on_load: nil)

    case Executions.get_execution_by_flow_and_public_id(socket.assigns.current_flow.id, public_id) do
      nil -> put_flash(socket, :error, gettext("That run was not found in this flow."))
      execution -> InspectorManager.open(socket, execution)
    end
  end

  defp inspect_on_load(socket), do: socket

  # Saves the flow and runs it with `input`, like the run button does.
  defp run_with(socket, input) do
    socket
    |> assign(next_run_input: input, run_section_id: nil)
    |> push_event("request_save_and_run", %{})
  end

  defp import_error(:invalid_json), do: gettext("That file isn't JSON.")
  defp import_error(:not_a_flow), do: gettext("That file isn't a Heddle flow.")
  defp import_error(:too_big), do: gettext("That file is too big to be a flow.")

  defp import_error(reason) when is_binary(reason),
    do: gettext("That flow can't be imported: %{reason}.", reason: reason)

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
    # It runs as the drawer is typed in, so a definition may be half written.
    Enum.reduce(config_data, socket, fn
      {_key, "ui do" <> _rest = value}, acc_socket ->
        with {:ok, ui_fields} <- HeddleUI.CodeParser.parse_ui_definition(value),
             inputs = for(%{type: "input", name: name} <- ui_fields, do: name),
             outputs = for(%{type: "output", name: name} <- ui_fields, do: name),
             true <- inputs != [] or outputs != [] do
          push_event(acc_socket, "update_node_sockets", %{
            nodeId: node_id,
            inputs: inputs,
            outputs: outputs
          })
        else
          _nothing -> acc_socket
        end

      _other, acc_socket ->
        acc_socket
    end)
  end

  # A run that starts at a Webhook asks for the request first.
  defp run_or_ask(socket, data) do
    graph = run_graph(data, socket.assigns.run_section_id)

    if socket.assigns.next_run_input == nil and starts_at_webhook?(graph) do
      assign(socket,
        webhook_test_open: true,
        webhook_test_error: nil,
        webhook_test_fields: Graph.body_fields(graph)
      )
    else
      save_and_run(socket, data)
    end
  end

  defp run_graph(data, section_id) do
    flow = %{nodes: data["nodes"], connections: data["connections"], comments: data["comments"]}

    Graph.new(flow, section: section_id)
  end

  defp read_only(socket) do
    put_flash(
      socket,
      :error,
      gettext("Your role in this workspace lets you see this flow, not change it.")
    )
  end

  defp save_and_run(%{assigns: %{can_run: false}} = socket, _data) do
    put_flash(socket, :error, gettext("Your role in this workspace can't run flows."))
  end

  # The draft is saved as people change it, so a run takes it as it is now, everyone's
  # changes in it. The canvas sent what it had before asking.
  defp save_and_run(socket, _data) do
    %{current_scope: scope, current_flow: flow, next_run_input: input} = socket.assigns
    input = run_input(input, socket.assigns.run_section_id)
    socket = assign(socket, next_run_input: nil, run_section_id: nil)

    case Executions.run(scope, flow, input, version: :draft) do
      {:ok, execution} ->
        socket
        |> assign(execution_notice: nil)
        |> InspectorManager.follow(execution)

      {:error, _reason} ->
        put_flash(socket, :error, gettext("The flow could not be started."))
    end
  end

  # A run from the editor takes the pinned data, and tells the inspector each step.
  defp run_input(nil, nil), do: %{"trigger" => "manual", "debug" => true}

  defp run_input(nil, section_id),
    do: %{"trigger" => "section", "section_id" => section_id, "debug" => true}

  defp run_input(input, nil), do: Map.put(input, "debug", true)

  defp run_input(input, section_id),
    do: Map.merge(input, %{"section_id" => section_id, "debug" => true})

  # With a Start, a person can run the flow as it is. A Webhook needs a request.
  defp starts_at_webhook?(graph) do
    Graph.of_type(graph, "Webhook") != [] and Graph.of_type(graph, "Start") == []
  end

  defp webhook_test_form(params), do: to_form(params, as: :webhook_test)

  defp flow_settings_form(flow),
    do: to_form(%{"error_flow_id" => flow.error_flow_id}, as: :flow_settings)

  defp decode_body(body) do
    case String.trim(body || "") do
      "" -> {:ok, %{}}
      json -> with {:error, _reason} <- Jason.decode(json), do: :error
    end
  end

  defp execution_notice(:queued, execution) do
    %{
      kind: :info,
      status: "queued",
      title: "Execution queued",
      message: "The flow was saved and is waiting for the worker to run.",
      execution_id: execution.id,
      public_id: execution.public_id
    }
  end

  defp execution_notice("succeeded", execution) do
    %{
      kind: :success,
      status: "succeeded",
      title: "Execution finished",
      message: "The flow run is ready to inspect.",
      execution_id: execution.id,
      public_id: execution.public_id
    }
  end

  defp execution_notice("failed", execution) do
    %{
      kind: :error,
      status: "failed",
      title: "Execution failed",
      message: "The flow run finished with an error. Open it to inspect the details.",
      execution_id: execution.id,
      public_id: execution.public_id
    }
  end

  defp execution_notice("waiting", execution) do
    %{
      kind: :info,
      status: "waiting",
      title: gettext("Execution waiting"),
      message: gettext("The flow is paused at a Wait, and goes on by itself when the wait ends."),
      execution_id: execution.id,
      public_id: execution.public_id
    }
  end

  defp execution_notice(_status, execution) do
    %{
      kind: :info,
      status: "running",
      title: "Execution running",
      message: "The worker is processing this flow run.",
      execution_id: execution.id,
      public_id: execution.public_id
    }
  end

  defp subflow_options(socket, %{"type" => "Subflow"}) do
    %{current_scope: scope, current_flow: flow} = socket.assigns
    for other <- Flows.list_flows(scope), other.id != flow.id, do: {other.name, other.id}
  end

  defp subflow_options(_socket, _node_data), do: []
end
