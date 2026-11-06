defmodule HeddleUI.Components.ChatComponent do
  use HeddleUI, :live_component

  alias HeddleUI.AIChat

  attr :open, :boolean, default: false
  attr :messages, :list, default: []
  attr :loading, :boolean, default: false
  attr :confirmation, :map, default: nil
  attr :on_toggle, :string, default: "toggle_chat"
  attr :on_send, :string, default: "send_message"
  attr :node_config_open, :boolean, default: false

  def render(assigns) do
    ~H"""
    <div>
      <%= unless @open or @node_config_open do %>
        <.button
          phx-click={JS.push(@on_toggle) |> JS.focus(to: "#chat-input-field")}
          variant="primary"
          id="chat-open-button"
          class="fixed bottom-6 right-6 z-[99] p-4 rounded-full shadow-lg group w-14 h-14"
          title="AI Chat"
        >
          <.icon
            name="hero-chat-bubble-left-right"
            class="h-6 w-6 group-hover:scale-110 transition-transform"
          />
        </.button>
      <% end %>

      <div class={"fixed top-0 right-0 h-full w-[350px] bg-white dark:bg-slate-900 shadow-2xl z-[100] transform transition-transform duration-300 ease-in-out flex flex-col border-l border-gray-200 dark:border-slate-800 " <> if(@open, do: "translate-x-0", else: "translate-x-full")}>
        <div class="p-4 border-b border-gray-200 dark:border-slate-800 flex items-center justify-between bg-gray-50 dark:bg-slate-800">
          <div class="flex items-center gap-2">
            <div class="w-8 h-8 rounded bg-primary/10 flex items-center justify-center text-primary">
              <svg
                xmlns="http://www.w3.org/2000/svg"
                class="h-5 w-5"
                viewBox="0 0 24 24"
                fill="currentColor"
              >
                <path d="M12 2a2 2 0 012 2c0 .74-.4 1.39-1 1.73V7h1a7 7 0 017 7h1a1 1 0 011 1v3a1 1 0 01-1 1h-1v1a2 2 0 01-2 2H5a2 2 0 01-2-2v-1H2a1 1 0 01-1-1v-3a1 1 0 011-1h1a7 7 0 017-7h1V5.73c-.6-.34-1-.99-1-1.73a2 2 0 012-2zM9 11a2 2 0 100 4 2 2 0 000-4zm6 0a2 2 0 100 4 2 2 0 000-4z" />
              </svg>
            </div>
            <span class="font-semibold text-gray-900 dark:text-white">AI Assistant</span>
          </div>

          <.button
            variant="ghost"
            phx-click={@on_toggle}
            class="p-1"
            title="Close Chat"
          >
            <.icon name="hero-x-mark" class="h-6 w-6" />
          </.button>
        </div>

        <div class="flex-1 overflow-y-auto p-4 space-y-4" id="chat-messages" phx-hook="ScrollToBottom">
          <%= for {role, content} <- @messages, not (role == :ai and content == "") do %>
            <div class={"flex " <> if(role == :user, do: "justify-end", else: "justify-start")}>
              <div class={"max-w-[85%] rounded-2xl px-4 py-3 text-sm " <>
                if(role == :user,
                  do: "bg-primary text-primary-content rounded-br-none shadow-sm dark:shadow-none",
                  else: "bg-gray-100 dark:bg-slate-800 text-gray-800 dark:text-gray-200 rounded-bl-none border border-gray-200 dark:border-slate-700 shadow-sm dark:shadow-none")}>
                <%= cond do %>
                  <% role == :ai and streaming_flow?({role, content}, @messages, @loading) -> %>
                    <div class="flex items-center gap-2 text-primary font-medium italic animate-pulse">
                      <.icon name="hero-arrow-path" class="h-4 w-4 animate-spin" />
                      {gettext("Constructing flow...")}
                    </div>
                  <% role == :ai and AIChat.flow_json?(content) -> %>
                    {gettext("I couldn't build this flow. Tell me what to change and I'll try again.")}
                  <% true -> %>
                    {content}
                <% end %>
              </div>
            </div>
          <% end %>

          <%= if @loading and (List.last(@messages) |> elem(1)) == "" do %>
            <div class="flex justify-start">
              <div class="max-w-[85%] rounded-2xl px-4 py-3 text-sm bg-gray-100 dark:bg-slate-800 text-gray-800 dark:text-gray-200 rounded-bl-none border border-gray-200 dark:border-slate-700 shadow-sm dark:shadow-none">
                <div class="flex items-center gap-2 text-primary font-medium italic animate-pulse">
                  <svg
                    class="animate-spin h-4 w-4"
                    xmlns="http://www.w3.org/2000/svg"
                    fill="none"
                    viewBox="0 0 24 24"
                  >
                    <circle
                      class="opacity-25"
                      cx="12"
                      cy="12"
                      r="10"
                      stroke="currentColor"
                      stroke-width="4"
                    >
                    </circle>

                    <path
                      class="opacity-75"
                      fill="currentColor"
                      d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
                    >
                    </path>
                  </svg>
                  Thinking...
                </div>
              </div>
            </div>
          <% end %>

          <%= if Enum.empty?(@messages) do %>
            <div class="flex flex-col items-center justify-center h-full text-gray-400 dark:text-gray-400 text-sm italic">
              <svg
                xmlns="http://www.w3.org/2000/svg"
                class="h-12 w-12 mb-2 opacity-50"
                fill="none"
                viewBox="0 0 24 24"
                stroke="currentColor"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="1.5"
                  d="M19 11a7 7 0 01-7 7m0 0a7 7 0 01-7-7m7 7v4m0 0H8m4 0h4m-4-8a3 3 0 01-3-3V5a3 3 0 116 0v6a3 3 0 01-3 3z"
                />
              </svg>
              <p>How can I help you with your flow?</p>
            </div>
          <% end %>
        </div>

        <div
          :if={assigns[:confirmation]}
          id="agent-run-confirmation"
          class="p-4 border-t border-gray-200 dark:border-slate-800 bg-amber-50 dark:bg-amber-900/20"
        >
          <p class="text-sm font-medium text-gray-900 dark:text-white">
            {gettext("Run \"%{flow}\"?", flow: @confirmation.flow_name)}
          </p>
          <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">
            {gettext("The agent wants to run this flow, which can have real side effects.")}
          </p>
          <div class="mt-3 flex items-center gap-2">
            <.button
              id="agent-run-approve"
              phx-click="agent_run_decision"
              phx-value-decision="approve"
              variant="primary"
            >
              {gettext("Run")}
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
              placeholder={if @loading, do: "AI is thinking...", else: "Message AI..."}
              disabled={@loading}
              onkeydown="if(event.key === 'Enter' && !event.shiftKey) { event.preventDefault(); this.form.dispatchEvent(new Event('submit', {bubbles: true, cancelable: true})); }"
              class={["flex-1 w-full mb-0", if(@loading, do: "cursor-not-allowed opacity-60")]}
              rows="3"
            />
            <.button
              type="submit"
              disabled={@loading}
              variant="primary"
              title={gettext("Send")}
              class="!p-0 w-[42px] h-[42px] flex-shrink-0"
            >
              <%= if @loading do %>
                <.icon name="hero-arrow-path" class="w-4 h-4 animate-spin" />
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

  # Only the last reply can still be coming in. One that ended without becoming a flow
  # must not keep spinning.
  defp streaming_flow?({_role, content} = message, messages, loading) do
    loading and message == List.last(messages) and AIChat.flow_json?(content)
  end
end
