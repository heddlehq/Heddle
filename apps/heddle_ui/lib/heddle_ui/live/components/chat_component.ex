defmodule HeddleUI.Components.ChatComponent do
  use HeddleUI, :live_component

  attr :open, :boolean, default: false
  attr :agent, :map, required: true
  attr :waiting, :boolean, default: false
  attr :history_open, :boolean, default: false
  attr :history, :list, default: []
  attr :terminal_open, :boolean, default: false
  attr :on_toggle, :string, default: "toggle_chat"
  attr :on_send, :string, default: "send_message"
  attr :node_config_open, :boolean, default: false

  def render(assigns) do
    assigns = assign(assigns, :busy, assigns.waiting or assigns.agent.status == "running")

    ~H"""
    <div>
      <%= unless @open or @node_config_open do %>
        <.button
          phx-click={JS.push(@on_toggle) |> JS.focus(to: "#chat-input-field")}
          variant="primary"
          id="chat-open-button"
          class={[
            "fixed right-6 z-[99] p-4 rounded-full shadow-lg group w-14 h-14 transition-[bottom]",
            if(@terminal_open, do: "bottom-[calc(45vh+1.5rem)]", else: "bottom-6")
          ]}
          title="AI Chat"
        >
          <.icon
            name="hero-chat-bubble-left-right"
            class="h-6 w-6 group-hover:scale-110 transition-transform"
          />
        </.button>
      <% end %>

      <div class={"fixed top-0 right-0 h-full w-[420px] max-w-full bg-white dark:bg-slate-900 shadow-2xl z-[100] transform transition-transform duration-300 ease-in-out flex flex-col border-l border-gray-200 dark:border-slate-800 " <> if(@open, do: "translate-x-0", else: "translate-x-full")}>
        <div class="p-4 border-b border-gray-200 dark:border-slate-800 flex items-center justify-between bg-gray-50 dark:bg-slate-800">
          <div class="flex items-center gap-2">
            <div class="w-8 h-8 rounded bg-primary/10 flex items-center justify-center text-primary">
              <.icon name="hero-sparkles" class="h-5 w-5" />
            </div>
            <span class="font-semibold text-gray-900 dark:text-white">{gettext("Agent")}</span>
          </div>

          <div class="flex items-center gap-1">
            <.button
              id="agent-new-chat"
              variant="ghost"
              phx-click="agent_new_chat"
              disabled={@busy}
              class="p-1"
              title={gettext("New chat")}
            >
              <.icon name="hero-plus" class="h-5 w-5" />
            </.button>
            <.button
              id="agent-history-toggle"
              variant="ghost"
              phx-click="agent_toggle_history"
              class="p-1"
              title={gettext("Previous chats")}
            >
              <.icon name="hero-clock" class="h-5 w-5" />
            </.button>
            <.button
              variant="ghost"
              phx-click={@on_toggle}
              class="p-1"
              title={gettext("Close chat")}
            >
              <.icon name="hero-x-mark" class="h-6 w-6" />
            </.button>
          </div>
        </div>

        <div
          :if={@history_open}
          id="agent-history"
          class="flex-1 space-y-1 overflow-y-auto p-3"
        >
          <p
            :if={@history == []}
            class="p-4 text-center text-sm text-gray-500 dark:text-gray-400"
          >
            {gettext("No previous chats about this flow.")}
          </p>
          <button
            :for={conversation <- @history}
            id={"agent-conversation-#{conversation.id}"}
            type="button"
            phx-click="agent_open_conversation"
            phx-value-id={conversation.id}
            disabled={@busy}
            class="block w-full rounded-lg px-3 py-2 text-left transition hover:bg-gray-100 disabled:opacity-50 dark:hover:bg-slate-800"
          >
            <span class="block truncate text-sm font-medium text-gray-900 dark:text-white">
              {conversation.title}
            </span>
            <span class="block text-xs text-gray-500 dark:text-gray-400">
              {Calendar.strftime(conversation.updated_at, "%d/%m/%Y %H:%M")}
            </span>
          </button>
        </div>

        <div
          :if={not @history_open}
          class="flex-1 overflow-y-auto p-4 space-y-3"
          id="chat-messages"
          phx-hook="ScrollToBottom"
        >
          <%= for item <- @agent.items do %>
            <.chat_item item={item} />
          <% end %>

          <div
            :if={@busy}
            id="agent-working"
            class="flex items-center gap-2 px-1 text-xs font-medium text-gray-500 dark:text-gray-400"
          >
            <.icon name="hero-arrow-path" class="h-3.5 w-3.5 animate-spin text-primary" />
            {gettext("Working...")}
          </div>

          <div
            :if={@agent.items == [] and not @busy}
            class="flex flex-col items-center justify-center h-full gap-2 px-6 text-center text-sm text-gray-500 dark:text-gray-400"
          >
            <.icon name="hero-sparkles" class="h-10 w-10 opacity-50" />
            <p>
              {gettext("Ask for a change or just say what is wrong. I read the flow and its runs.")}
            </p>
          </div>
        </div>

        <div
          :if={@agent.permission}
          id="agent-run-confirmation"
          class="p-4 border-t border-gray-200 dark:border-slate-800 bg-amber-50 dark:bg-amber-900/20"
        >
          <p class="text-sm font-medium text-gray-900 dark:text-white">
            {gettext("Run \"%{flow}\"?", flow: @agent.permission.flow_name)}
          </p>
          <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">
            {gettext("The agent wants to run this flow, which can have real side effects.")}
          </p>
          <div class="mt-3 flex flex-wrap items-center gap-2">
            <.button
              id="agent-run-approve"
              phx-click="agent_run_decision"
              phx-value-decision="once"
              variant="primary"
            >
              {gettext("Run")}
            </.button>
            <.button
              id="agent-run-always"
              phx-click="agent_run_decision"
              phx-value-decision="always"
              variant="ghost"
            >
              {gettext("Always in this chat")}
            </.button>
            <.button
              id="agent-run-deny"
              phx-click="agent_run_decision"
              phx-value-decision="deny"
              variant="ghost"
            >
              {gettext("Don't run")}
            </.button>
          </div>
        </div>

        <div class="p-4 border-t border-gray-200 dark:border-slate-800 bg-white dark:bg-slate-900">
          <form phx-submit={@on_send} class="flex gap-2 items-center">
            <.textarea
              name="content"
              id="chat-input-field"
              placeholder={gettext("Message the agent...")}
              disabled={@busy}
              onkeydown="if(event.key === 'Enter' && !event.shiftKey) { event.preventDefault(); this.form.dispatchEvent(new Event('submit', {bubbles: true, cancelable: true})); }"
              class={["flex-1 w-full mb-0", if(@busy, do: "cursor-not-allowed opacity-60")]}
              rows="3"
            />
            <%= if @busy do %>
              <.button
                id="agent-stop"
                type="button"
                phx-click="agent_stop"
                variant="ghost"
                title={gettext("Stop")}
                class="!p-0 w-[42px] h-[42px] flex-shrink-0"
              >
                <.icon name="hero-stop-solid" class="w-5 h-5" />
              </.button>
            <% else %>
              <.button
                type="submit"
                variant="primary"
                title={gettext("Send")}
                class="!p-0 w-[42px] h-[42px] flex-shrink-0"
              >
                <.icon name="hero-paper-airplane-solid" class="w-5 h-5" />
              </.button>
            <% end %>
          </form>
        </div>
      </div>
    </div>
    """
  end

  attr :item, :map, required: true

  defp chat_item(%{item: %{role: "tool"}} = assigns) do
    assigns =
      assign(assigns,
        details_id: "agent-tool-details-#{assigns.item.id}",
        summary: tool_summary(assigns.item)
      )

    ~H"""
    <div
      id={"agent-tool-#{@item.id}"}
      data-status={@item.status}
      class="rounded-lg border border-gray-200 bg-gray-50 text-xs dark:border-slate-700 dark:bg-slate-800/60"
    >
      <button
        type="button"
        phx-click={JS.toggle(to: "##{@details_id}")}
        class="flex w-full items-center gap-2 px-3 py-2 text-left transition hover:bg-gray-100 dark:hover:bg-slate-800"
      >
        <%= case @item.status do %>
          <% "running" -> %>
            <.icon name="hero-arrow-path" class="size-4 flex-shrink-0 animate-spin text-primary" />
          <% "ok" -> %>
            <.icon name="hero-check-circle" class="size-4 flex-shrink-0 text-primary" />
          <% _failed -> %>
            <.icon name="hero-x-circle" class="size-4 flex-shrink-0 text-error" />
        <% end %>
        <span class="font-medium text-gray-900 dark:text-white">{tool_title(@item.name)}</span>
        <span :if={@summary} class="min-w-0 flex-1 truncate text-gray-500 dark:text-gray-400">
          {@summary}
        </span>
        <.icon name="hero-chevron-down" class="ml-auto size-3 flex-shrink-0 text-gray-400" />
      </button>

      <div id={@details_id} class="hidden border-t border-gray-200 px-3 py-2 dark:border-slate-700">
        <pre
          :if={@item.args != %{}}
          class="max-h-64 overflow-auto whitespace-pre-wrap break-all font-mono text-[11px] leading-relaxed text-gray-700 dark:text-gray-300"
        >{pretty(@item.args)}</pre>
        <pre
          :if={@item.output}
          class="mt-2 max-h-64 overflow-auto whitespace-pre-wrap break-all font-mono text-[11px] leading-relaxed text-gray-700 dark:text-gray-300"
        >{pretty(@item.output)}</pre>
      </div>
    </div>
    """
  end

  defp chat_item(%{item: %{role: "error"}} = assigns) do
    ~H"""
    <div class="rounded-lg border border-error/40 bg-error/10 px-3 py-2 text-sm text-gray-900 dark:text-white">
      {@item.text}
    </div>
    """
  end

  defp chat_item(assigns) do
    ~H"""
    <div class={["flex", if(@item.role == "user", do: "justify-end", else: "justify-start")]}>
      <div class={[
        "max-w-[90%] break-words rounded-2xl px-4 py-3 text-sm",
        if(@item.role == "user",
          do: "bg-primary text-primary-content rounded-br-none shadow-sm dark:shadow-none",
          else:
            "bg-gray-100 dark:bg-slate-800 text-gray-800 dark:text-gray-200 rounded-bl-none border border-gray-200 dark:border-slate-700 shadow-sm dark:shadow-none"
        )
      ]}>
        <%!-- The span keeps the indentation of this template out of the pre-wrap. --%>
        <span class="whitespace-pre-wrap">{String.trim(@item.text)}</span>
      </div>
    </div>
    """
  end

  defp tool_title("list_flows"), do: gettext("Listing flows")
  defp tool_title("get_flow"), do: gettext("Reading the flow")
  defp tool_title("list_nodes"), do: gettext("Checking the nodes")
  defp tool_title("list_executions"), do: gettext("Checking the runs")
  defp tool_title("get_execution"), do: gettext("Reading a run")
  defp tool_title("update_flow"), do: gettext("Changing the flow")
  defp tool_title("create_flow"), do: gettext("Creating a flow")
  defp tool_title("test_flow"), do: gettext("Testing the flow")
  defp tool_title("run_flow"), do: gettext("Running the flow")
  defp tool_title(name), do: name

  # What tells this call from the others, at a glance.
  defp tool_summary(%{name: "test_flow", output: output}) when is_binary(output) do
    case Jason.decode(output) do
      {:ok, %{"status" => "failed", "error" => %{"message" => message}}} -> message
      {:ok, %{"status" => status}} -> status
      _other -> nil
    end
  end

  defp tool_summary(%{name: "test_flow", args: args}),
    do: compact(args["webhook"] || args["input"])

  defp tool_summary(%{name: "get_execution", args: args}), do: args["execution_id"]

  defp tool_summary(%{name: "update_flow", args: %{"nodes" => nodes}}) when is_list(nodes) do
    ngettext("1 node", "%{count} nodes", length(nodes))
  end

  defp tool_summary(_item), do: nil

  defp compact(nil), do: nil
  defp compact(value), do: Jason.encode!(value)

  defp pretty(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, decoded} when is_map(decoded) or is_list(decoded) -> pretty(decoded)
      _other -> value
    end
  end

  defp pretty(value), do: Jason.encode!(value, pretty: true)
end
