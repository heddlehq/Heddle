defmodule HeddleUI.FlowLive.AICreator do
  use HeddleUI, :live_view

  on_mount {HeddleUI.UserAuth, :require_system_admin}

  alias HeddleCore.Flows
  alias HeddleAI.Agents.FlowPlanner
  alias HeddleUI.AIChat

  @impl true
  def mount(_params, _session, socket) do
    if HeddleAI.LLM.configured?() do
      {:ok,
       assign(socket,
         page_title: gettext("Create Flow with AI"),
         messages: [],
         loading: false,
         plan_ready: false,
         ai_configured: true
       )}
    else
      {:ok,
       socket
       |> put_flash(:error, gettext("No LLM provider is configured."))
       |> push_navigate(to: ~p"/flows")
       |> assign(ai_configured: false)}
    end
  end

  @impl true
  def handle_event("send_message", %{"content" => ""}, socket) do
    {:noreply, socket}
  end

  def handle_event("send_message", %{"content" => content}, socket) do
    {:noreply, ask_planner(socket, content)}
  end

  @impl true
  def handle_event("approve_plan", _params, socket) do
    {:noreply, ask_planner(socket, gettext("Looks good! Please build this flow."))}
  end

  @impl true
  def handle_async(:ai_stream, {:ok, _result}, socket) do
    case List.last(socket.assigns.messages) do
      {:ai, content} -> {:noreply, finish_reply(socket, content)}
      _ -> {:noreply, assign(socket, loading: false)}
    end
  end

  @impl true
  def handle_async(:ai_stream, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> put_flash(:error, gettext("AI Stream failed: %{reason}", reason: inspect(reason)))
     |> assign(loading: false)}
  end

  @impl true
  def handle_info({:chat_stream_chunk, chunk}, socket) do
    {:noreply, assign(socket, messages: AIChat.append_chunk(socket.assigns.messages, chunk))}
  end

  @impl true
  def handle_info({:chat_stream_error, reason}, socket) do
    {:noreply,
     socket
     |> put_flash(:error, gettext("AI Error: %{reason}", reason: inspect(reason)))
     |> assign(loading: false)}
  end

  defp ask_planner(socket, content) do
    messages = socket.assigns.messages ++ [{:user, content}, {:ai, ""}]
    ai_messages = AIChat.to_api_messages(messages)
    parent = self()
    locale = socket.assigns.locale
    planner = Application.get_env(:heddle_ui, :flow_planner, FlowPlanner)

    socket
    |> assign(messages: messages, loading: true, plan_ready: false)
    |> start_async(:ai_stream, fn ->
      {:ok, result} = planner.chat(ai_messages, nil, locale)
      AIChat.consume_stream(result.stream, parent)
    end)
  end

  defp finish_reply(socket, content) do
    case AIChat.extract_create_flow_json(content) do
      {:ok, json} -> create_flow(socket, json)
      :error -> assign(socket, loading: false, plan_ready: AIChat.plan_proposed?(content))
    end
  end

  defp create_flow(socket, json) do
    attrs = %{
      name: json["name"] || "AI Generated Flow",
      nodes: json |> Map.get("nodes", []) |> AIChat.normalize_nodes(),
      connections: Map.get(json, "connections", [])
    }

    case Flows.create_flow(socket.assigns.current_scope, attrs) do
      {:ok, flow} ->
        socket
        |> put_flash(:info, gettext("Flow created successfully!"))
        |> push_navigate(to: ~p"/flows/#{flow.id}")

      {:error, _changeset} ->
        socket
        |> put_flash(:error, gettext("Failed to create flow from AI."))
        |> assign(loading: false)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex-1 min-h-0 flex flex-col bg-gray-50 dark:bg-slate-950 overflow-hidden">
      <!-- Top header -->
      <div class="bg-white dark:bg-slate-900 border-b border-gray-200 dark:border-slate-800 px-6 py-4 flex items-center justify-between shadow-sm">
        <div class="flex items-center gap-3">
          <div class="w-10 h-10 rounded-xl bg-primary/10 flex items-center justify-center text-primary">
            <svg class="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M19.428 15.428a2 2 0 00-1.022-.547l-2.387-.477a6 6 0 00-3.86.517l-.318.158a6 6 0 01-3.86.517L6.05 15.21a2 2 0 00-1.806.547M8 4h8l-1 1v5.172a2 2 0 00.586 1.414l5 5c1.26 1.26.367 3.414-1.415 3.414H4.828c-1.782 0-2.674-2.154-1.414-3.414l5-5A2 2 0 009 10.172V5L8 4z"
              />
            </svg>
          </div>
          <div>
            <h1 class="text-lg font-bold text-gray-900 dark:text-white">
              {gettext("AI Flow Creator")}
            </h1>
            <p class="text-xs text-gray-500 dark:text-gray-400">
              {gettext("Describe the workflow you want, and let AI build the nodes and connections.")}
            </p>
          </div>
        </div>
        <.button navigate={~p"/flows"} variant="ghost" class="text-sm">
          {gettext("Cancel")}
        </.button>
      </div>
      
    <!-- Chat messages area -->
      <div
        class="flex-1 overflow-y-auto p-6 space-y-6 max-w-4xl mx-auto w-full"
        id="chat-messages-container"
        phx-hook="ScrollToBottom"
      >
        <%= if Enum.empty?(@messages) do %>
          <div class="h-full flex flex-col items-center justify-center text-center py-12">
            <div class="w-16 h-16 rounded-full bg-primary/10 text-primary flex items-center justify-center mb-4">
              <svg class="w-8 h-8" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="1.5"
                  d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z"
                />
              </svg>
            </div>
            <h3 class="text-lg font-semibold text-gray-900 dark:text-white mb-2">
              {gettext("How can I help you automate today?")}
            </h3>
            <p class="text-sm text-gray-500 dark:text-gray-400 max-w-md mb-8">
              {gettext(
                "You can say things like \"Fetch data from an API and send a webhook\" or \"Set a variable and evaluate some python code\"."
              )}
            </p>
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-3 max-w-lg w-full">
              <button
                phx-click="send_message"
                phx-value-content={
                  gettext("Create a flow with a webhook that receives data, and logs the output")
                }
                class="p-3 text-left bg-white dark:bg-slate-900 border border-gray-200 dark:border-slate-800 rounded-xl hover:border-primary transition-colors text-xs text-gray-700 dark:text-gray-300 shadow-sm"
              >
                "{gettext("Create a flow with a webhook that receives data, and logs the output")}"
              </button>
              <button
                phx-click="send_message"
                phx-value-content={
                  gettext("Fetch data via HTTP request and run Python evaluation logic")
                }
                class="p-3 text-left bg-white dark:bg-slate-900 border border-gray-200 dark:border-slate-800 rounded-xl hover:border-primary transition-colors text-xs text-gray-700 dark:text-gray-300 shadow-sm"
              >
                "{gettext("Fetch data via HTTP request and run Python evaluation logic")}"
              </button>
            </div>
          </div>
        <% else %>
          <%= for {sender, content} <- @messages do %>
            <div class={"flex gap-4 #{if sender == :user, do: "justify-end", else: "justify-start"}"}>
              <%= if sender == :ai do %>
                <div class="w-8 h-8 rounded-lg bg-primary flex items-center justify-center text-primary-content shrink-0 text-xs font-bold">
                  AI
                </div>
              <% end %>
              <div class={"max-w-[80%] rounded-2xl px-5 py-3.5 shadow-sm #{if sender == :user, do: "bg-primary text-primary-content rounded-br-none", else: "bg-white dark:bg-slate-900 border border-gray-200 dark:border-slate-800 text-gray-800 dark:text-gray-200 rounded-bl-none"}"}>
                <%= if sender == :ai do %>
                  <div class="prose dark:prose-invert text-sm max-w-none prose-p:leading-relaxed prose-pre:bg-gray-800 prose-pre:text-gray-100">
                    <%= cond do %>
                      <% content == "" and @loading -> %>
                        <div class="flex items-center gap-2 text-gray-400">
                          <.icon name="hero-arrow-path" class="w-4 h-4 animate-spin" />
                          <span>{gettext("Thinking and designing your flow...")}</span>
                        </div>
                      <% @loading and AIChat.flow_json?(content) -> %>
                        <div class="flex items-center gap-2 text-gray-400">
                          <.icon name="hero-arrow-path" class="w-4 h-4 animate-spin" />
                          <span>{gettext("Building flow and rendering graph...")}</span>
                        </div>
                      <% AIChat.flow_json?(content) -> %>
                        <p>
                          {gettext(
                            "I couldn't build this flow. Tell me what to change and I'll try again."
                          )}
                        </p>
                      <% true -> %>
                        <p class="whitespace-pre-wrap">{AIChat.display_text(content)}</p>
                    <% end %>
                  </div>
                <% else %>
                  <p class="text-sm whitespace-pre-wrap">{content}</p>
                <% end %>
              </div>
              <%= if sender == :user do %>
                <div class="w-8 h-8 rounded-lg bg-gray-200 dark:bg-slate-700 flex items-center justify-center text-gray-700 dark:text-gray-300 shrink-0 text-xs font-bold">
                  {String.at(@current_scope.user.username || @current_scope.user.email, 0)
                  |> String.upcase()}
                </div>
              <% end %>
            </div>
          <% end %>

          <%= if @plan_ready and not @loading do %>
            <div
              id="ai-plan-approval"
              class="bg-primary/10 border border-primary/30 rounded-2xl p-5 flex flex-col sm:flex-row items-center justify-between gap-4 shadow-sm animate-fade-in"
            >
              <div>
                <h4 class="font-bold text-gray-900 dark:text-white text-sm">
                  {gettext("Are you happy with this implementation plan?")}
                </h4>
                <p class="text-xs text-gray-600 dark:text-gray-400 mt-0.5">
                  {gettext("Or reply below with adjustments")}
                </p>
              </div>
              <.button
                id="ai-approve-plan"
                phx-click="approve_plan"
                variant="primary"
                class="w-full sm:w-auto shrink-0"
              >
                <.icon name="hero-check" class="w-4 h-4.5" />
                {gettext("Yes, Build This Flow")}
              </.button>
            </div>
          <% end %>
        <% end %>
      </div>
      
    <!-- Input prompt bar -->
      <div class="p-4 bg-white dark:bg-slate-900 border-t border-gray-200 dark:border-slate-800">
        <div class="max-w-4xl mx-auto">
          <form phx-submit="send_message" class="flex gap-2">
            <input
              type="text"
              name="content"
              id="ai-flow-prompt-input"
              phx-hook="FocusInput"
              autocomplete="off"
              disabled={@loading}
              placeholder={gettext("Describe changes or explain what the flow should do...")}
              class="flex-1 bg-gray-50 dark:bg-slate-800 border-gray-200 dark:border-slate-700 rounded-xl px-4 py-3 text-sm focus:outline-none focus:ring-2 focus:ring-primary focus:border-primary dark:text-white"
            />
            <.button
              id="ai-flow-send-button"
              type="submit"
              variant="primary"
              disabled={@loading}
              title={gettext("Send")}
              class="px-5 rounded-xl"
            >
              <%= if @loading do %>
                <.icon name="hero-arrow-path" class="w-5 h-5 animate-spin" />
              <% else %>
                <.icon name="hero-paper-airplane-solid" class="w-5 h-5" />
              <% end %>
            </.button>
          </form>
        </div>
      </div>
    </div>
    """
  end
end
