defmodule HeddleUI.Components.Flow.FlowHeader do
  use HeddleUI, :html

  attr :has_changes, :boolean, required: true
  attr :flow, :any, required: true
  attr :renaming_flow, :boolean, default: false

  attr :can_replace, :boolean,
    default: false,
    doc: "whether importing would replace a flow on the canvas"

  def flow_header(assigns) do
    ~H"""
    <header class="flex items-center justify-between px-6 py-3 border-b border-gray-200 dark:border-slate-700 bg-white dark:bg-slate-800 z-10 h-16 shadow-md dark:shadow-black/50">
      <div class="flex items-center gap-4">
        <.link
          navigate={~p"/"}
          class="flex items-center gap-2 group transition-opacity hover:opacity-80"
        >
          <img
            src={~p"/images/logo.png"}
            alt="Heddle"
            class="w-9 h-9 object-contain"
          />
          <span class="text-lg font-bold bg-clip-text text-transparent bg-gradient-to-r from-gray-900 to-gray-600 dark:from-white dark:to-gray-400">
            Heddle
          </span>
        </.link>
        <div class="h-8 w-px bg-gray-200 dark:bg-slate-700 hidden sm:block"></div>

        <div class="hidden sm:block">
          <%= if @renaming_flow do %>
            <form
              phx-submit="save_flow_name"
              phx-click-away="cancel_rename_flow"
              class="flex items-center gap-2"
            >
              <input
                type="text"
                name="name"
                value={@flow.name}
                id="flow-name-input"
                phx-mounted={JS.focus()}
                class="px-2 py-1 text-sm font-bold text-gray-900 dark:text-white bg-white dark:bg-slate-900 border border-primary rounded focus:outline-none focus:ring-2 focus:ring-primary/50"
              />
              <.button
                type="submit"
                variant="ghost"
                class="p-1 px-2 text-green-600 hover:text-green-700 dark:text-green-400 dark:hover:text-green-300"
              >
                <.icon name="hero-check" class="w-4 h-4" />
              </.button>
            </form>
          <% else %>
            <div class="flex items-center gap-2 group/title">
              <h1 class="text-base font-bold text-gray-900 dark:text-white leading-tight">
                {@flow.name}
              </h1>

              <.button
                phx-click="edit_flow_name"
                variant="ghost"
                class="p-1 opacity-0 group-hover/title:opacity-100 transition-opacity"
                title="Rename Flow"
              >
                <.icon name="hero-pencil" class="w-4 h-4" />
              </.button>
            </div>
          <% end %>
        </div>
      </div>

      <div class="flex items-center gap-3">
        <.button
          href={~p"/flows"}
          variant="ghost"
          class="h-9 px-3"
          title="Go to Flows"
        >
          <.icon name="hero-squares-2x2" class="w-4 h-4" />
          <span class="hidden sm:inline">Flows</span>
        </.button>
        <.button
          id="import-flow"
          type="button"
          phx-hook="ImportFlow"
          variant="ghost"
          class="h-9 px-3"
          title={gettext("Import a flow from a JSON file")}
          data-replace={to_string(@can_replace)}
          data-confirm-replace={
            gettext("The imported flow takes the place of the one on the canvas. Import it?")
          }
        >
          <.icon name="hero-arrow-up-tray" class="w-4 h-4" />
          <span class="hidden sm:inline">{gettext("Import")}</span>
        </.button>
        <.button
          id="open-flow-settings"
          type="button"
          phx-click="open_flow_settings"
          variant="ghost"
          class="relative h-9 px-3"
          title={gettext("Flow settings")}
        >
          <.icon name="hero-cog-6-tooth" class="w-4 h-4" />
          <span class="hidden sm:inline">{gettext("Settings")}</span>
          <span
            :if={@flow.error_flow_id}
            class="absolute right-1.5 top-1.5 size-1.5 rounded-full bg-primary"
            title={gettext("This flow has an error flow")}
          />
        </.button>
        <div class="h-5 w-px bg-gray-200 dark:bg-slate-700 mx-1"></div>

        <.button
          phx-click="run_flow"
          variant="success"
          class="h-9 px-4"
        >
          <.icon name="hero-play" class="w-4 h-4" /> <span>Run Flow</span>
        </.button>
      </div>
    </header>

    <%!-- Always here: a sibling appearing would make LiveView move the canvas, and whatever is being typed on it would lose focus. --%>
    <div id="unsaved-changes">
      <%= if @has_changes do %>
        <div class="absolute bottom-6 left-1/2 transform -translate-x-1/2 bg-white dark:bg-slate-800 px-6 py-3 rounded-full shadow-lg dark:shadow-black/50 border border-gray-200 dark:border-slate-700 z-50 flex items-center gap-4 animate-bounce-in">
          <span class="text-sm font-medium text-gray-700 dark:text-slate-200">
            You have unsaved changes
          </span>
          <.button
            phx-click="save_graph"
            variant="success"
            class="px-6 py-2 rounded-full"
          >
            {gettext("Save Changes")}
          </.button>
        </div>
      <% end %>
    </div>
    """
  end
end
