defmodule HeddleUI.Components.Flow.TerminalPanel do
  @moduledoc """
  The terminal of the editor, which stays mounted while hidden so what runs in it goes on.
  """

  use HeddleUI, :html

  attr :open, :boolean, required: true
  attr :exited, :boolean, required: true
  attr :token, :string, required: true
  attr :flow_id, :integer, required: true
  attr :chat_open, :boolean, default: false

  def terminal_panel(assigns) do
    ~H"""
    <button
      :if={not @open}
      id="terminal-open-button"
      type="button"
      phx-click="terminal_toggle"
      title={gettext("Terminal")}
      class="fixed bottom-6 right-24 z-[99] flex size-14 items-center justify-center rounded-full border border-gray-200 bg-white text-gray-700 shadow-lg transition hover:text-primary dark:border-slate-700 dark:bg-slate-800 dark:text-slate-200"
    >
      <.icon name="hero-command-line" class="size-6" />
    </button>

    <section
      id="terminal-panel"
      class={[
        "h-[45vh] flex-shrink-0 flex-col border-t border-gray-200 bg-white transition-[margin] dark:border-slate-700 dark:bg-slate-900",
        if(@open, do: "flex", else: "hidden"),
        @chat_open && "mr-[420px]"
      ]}
    >
      <div class="flex items-center gap-3 border-b border-gray-200 px-4 py-2 dark:border-slate-700">
        <.icon name="hero-command-line" class="size-5 text-primary" />
        <span class="text-sm font-semibold text-gray-900 dark:text-white">{gettext("Terminal")}</span>
        <span class="text-xs text-gray-500 dark:text-gray-400">
          {gettext("Runs Claude Code on this machine. Sign in with your own account.")}
        </span>
        <.button
          :if={@exited}
          id="terminal-restart"
          variant="ghost"
          phx-click="terminal_restart"
          class="ml-auto px-2 py-1 text-xs"
        >
          {gettext("Start again")}
        </.button>
        <.button
          variant="ghost"
          phx-click="terminal_toggle"
          class={["p-1", if(@exited, do: "", else: "ml-auto")]}
          title={gettext("Hide")}
        >
          <.icon name="hero-chevron-down" class="size-5" />
        </.button>
      </div>
      <%!-- The padding stays out of the screen, or the fit counts it and cuts the last line. --%>
      <div class="min-h-0 flex-1 p-2">
        <div
          id="terminal-screen"
          phx-hook="Terminal"
          phx-update="ignore"
          data-token={@token}
          data-flow-id={@flow_id}
          class="h-full w-full"
        >
        </div>
      </div>
    </section>
    """
  end
end
