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
    <header class="relative flex items-center justify-between px-6 py-3 border-b border-gray-200 dark:border-slate-700 bg-white dark:bg-slate-800 z-20 h-16 shadow-md dark:shadow-black/50">
      <div class="flex items-center gap-4">
        <.link navigate={~p"/"} class="shrink-0 transition-opacity hover:opacity-80">
          <img src={~p"/images/logo.png"} alt="Heddle" class="w-8 h-8 object-contain" />
        </.link>

        <nav class="hidden sm:flex items-center gap-2 min-w-0">
          <.link
            navigate={~p"/flows"}
            class="text-sm font-medium text-gray-500 hover:text-gray-900 dark:text-gray-400 dark:hover:text-white transition-colors"
          >
            {gettext("Flows")}
          </.link>
          <span class="text-gray-300 dark:text-slate-600">/</span>
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
                :if={@can_edit}
                phx-click="edit_flow_name"
                variant="ghost"
                class="p-1 opacity-0 group-hover/title:opacity-100 transition-opacity"
                title={gettext("Rename flow")}
              >
                <.icon name="hero-pencil" class="w-3.5 h-3.5" />
              </.button>
              <button
                id="publish-status-versions"
                type="button"
                phx-click="versions_toggle"
                class={[
                  "rounded-full transition-shadow hover:ring-2 hover:ring-gray-200 dark:hover:ring-slate-600",
                  @versions_open && "ring-2 ring-gray-300 dark:ring-slate-500"
                ]}
                title={status_hint(@status) <> " " <> gettext("Click for the versions.")}
              >
                <.publish_status status={@status} number={@published_number} />
              </button>
              <%!-- The canvas says how saving goes, see collab.js: it shows only while
                   saving or reconnecting. The page leaves what is inside alone, attributes too. --%>
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
            </div>
          <% end %>
        </nav>
      </div>

      <div class="flex items-center gap-2">
        <%!-- Who else is on the canvas, see presence.js. The page leaves it alone. --%>
        <div id="presence-holder" phx-update="ignore" class="hidden sm:block mr-1">
          <div id="presence-avatars" class="flex items-center -space-x-1.5" data-count="0"></div>
        </div>

        <div class="relative">
          <.button
            id="flow-menu-button"
            type="button"
            variant="ghost"
            class={["relative h-9 px-2.5", @versions_open && "bg-gray-100 dark:bg-slate-700"]}
            phx-click={JS.toggle(to: "#flow-menu")}
            title={gettext("More")}
            aria-haspopup="menu"
          >
            <.icon name="hero-ellipsis-horizontal-mini" class="size-5" />
            <span
              :if={@flow.error_flow_id}
              class="absolute right-1.5 top-1.5 size-1.5 rounded-full bg-primary"
            />
          </.button>
          <div
            id="flow-menu"
            role="menu"
            phx-click-away={JS.hide(to: "#flow-menu")}
            class="hidden absolute right-0 top-full z-30 mt-2 w-56 rounded-lg border border-gray-200 bg-white p-1 shadow-lg dark:border-slate-700 dark:bg-slate-800"
          >
            <button
              id="open-versions"
              type="button"
              role="menuitem"
              phx-click={JS.hide(to: "#flow-menu") |> JS.push("versions_toggle")}
              class="flex w-full items-center gap-2 rounded-md px-3 py-2 text-left text-sm text-gray-700 hover:bg-gray-100 dark:text-gray-200 dark:hover:bg-slate-700"
            >
              <.icon name="hero-clock" class="w-4 h-4" />
              <span class="flex-1">{gettext("Versions")}</span>
              <.icon :if={@versions_open} name="hero-check-mini" class="size-4 text-primary" />
            </button>
            <button
              :if={@can_edit}
              id="open-flow-settings"
              type="button"
              role="menuitem"
              phx-click={JS.hide(to: "#flow-menu") |> JS.push("open_flow_settings")}
              class="flex w-full items-center gap-2 rounded-md px-3 py-2 text-left text-sm text-gray-700 hover:bg-gray-100 dark:text-gray-200 dark:hover:bg-slate-700"
            >
              <.icon name="hero-cog-6-tooth" class="w-4 h-4" />
              <span class="flex-1">{gettext("Settings")}</span>
              <span
                :if={@flow.error_flow_id}
                class="size-1.5 rounded-full bg-primary"
                title={gettext("This flow has an error flow")}
              />
            </button>
            <button
              id="import-flow"
              type="button"
              role="menuitem"
              phx-hook="ImportFlow"
              phx-click={JS.hide(to: "#flow-menu")}
              data-replace={to_string(@can_replace)}
              data-confirm-replace={
                gettext("The imported flow takes the place of the one on the canvas. Import it?")
              }
              class="flex w-full items-center gap-2 rounded-md px-3 py-2 text-left text-sm text-gray-700 hover:bg-gray-100 dark:text-gray-200 dark:hover:bg-slate-700"
            >
              <.icon name="hero-arrow-up-tray" class="w-4 h-4" />
              {gettext("Import from a file")}
            </button>
          </div>
        </div>

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
