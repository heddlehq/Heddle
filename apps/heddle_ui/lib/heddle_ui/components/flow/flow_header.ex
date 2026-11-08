defmodule HeddleUI.Components.Flow.FlowHeader do
  use HeddleUI, :html

  attr :flow, :any, required: true
  attr :renaming_flow, :boolean, default: false
  attr :can_edit, :boolean, default: true
  attr :can_run, :boolean, default: true

  attr :status, :atom,
    default: :unpublished,
    doc: "`:unpublished`, `:changed` or `:published`, see `HeddleUI.FlowLive.VersionsManager`"

  attr :published_number, :any, default: nil
  attr :versions_open, :boolean, default: false

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

              <.publish_status status={@status} number={@published_number} />
              <%!-- The canvas says how saving goes, see collab.js. The page leaves what is
                   inside alone, attributes too. --%>
              <span :if={@can_edit} id="save-state-holder" phx-update="ignore">
                <span
                  id="save-state"
                  data-state="saving"
                  class="save-state text-xs text-gray-500 dark:text-gray-400"
                >
                  {gettext("Saving...")}
                </span>
              </span>
              <span
                :if={not @can_edit}
                id="flow-read-only"
                class="inline-flex items-center gap-1 rounded-full bg-gray-100 px-2 py-0.5 text-xs font-medium text-gray-600 dark:bg-slate-700 dark:text-gray-300"
              >
                <.icon name="hero-eye-mini" class="size-3.5" /> {gettext("View only")}
              </span>
              <.button
                :if={@can_edit}
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
          :if={@can_edit}
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
        <%!-- Who else is on the canvas, see presence.js. The page leaves it alone. --%>
        <div id="presence-holder" phx-update="ignore" class="hidden sm:block">
          <div id="presence-avatars" class="flex items-center -space-x-1.5" data-count="0"></div>
        </div>
        <.button
          id="open-versions"
          type="button"
          phx-click="versions_toggle"
          variant="ghost"
          class={["h-9 px-3", @versions_open && "bg-gray-100 dark:bg-slate-700"]}
          title={gettext("Versions")}
        >
          <.icon name="hero-clock" class="w-4 h-4" />
          <span class="hidden sm:inline">{gettext("Versions")}</span>
        </.button>
        <div class="h-5 w-px bg-gray-200 dark:bg-slate-700 mx-1"></div>

        <.button
          :if={@can_edit}
          id="publish-flow"
          type="button"
          phx-click="open_publish"
          variant="outline"
          class="h-9 px-4"
          title={gettext("Publish what the canvas has, for production to run it")}
        >
          <.icon name="hero-rocket-launch" class="w-4 h-4" />
          <span>{gettext("Publish")}</span>
        </.button>
        <.button
          :if={@can_run}
          phx-click="run_flow"
          variant="success"
          class="h-9 px-4"
        >
          <.icon name="hero-play" class="w-4 h-4" /> <span>Run Flow</span>
        </.button>
      </div>
    </header>
    """
  end

  attr :status, :atom, required: true
  attr :number, :any, default: nil

  defp publish_status(assigns) do
    ~H"""
    <span
      id="flow-publish-status"
      data-status={@status}
      class={[
        "inline-flex items-center gap-1.5 rounded-full px-2 py-0.5 text-xs font-medium",
        @status == :published &&
          "bg-emerald-50 text-emerald-700 dark:bg-emerald-500/15 dark:text-emerald-300",
        @status == :changed && "bg-amber-50 text-amber-800 dark:bg-amber-500/15 dark:text-amber-300",
        @status == :unpublished && "bg-gray-100 text-gray-600 dark:bg-slate-700 dark:text-gray-300"
      ]}
      title={status_hint(@status)}
    >
      <span class={[
        "size-1.5 rounded-full",
        @status == :published && "bg-emerald-500",
        @status == :changed && "bg-amber-500",
        @status == :unpublished && "bg-gray-400"
      ]}>
      </span>
      <%= case @status do %>
        <% :published -> %>
          {gettext("Live · v%{number}", number: @number)}
        <% :changed -> %>
          {gettext("Unpublished changes")}
        <% :unpublished -> %>
          {gettext("Not published")}
      <% end %>
    </span>
    """
  end

  defp status_hint(:published), do: gettext("Production runs what the canvas has.")

  defp status_hint(:changed),
    do: gettext("Production runs the last version published, not what the canvas has.")

  defp status_hint(:unpublished),
    do: gettext("Webhooks, schedules and the API don't run this flow until it is published.")
end
