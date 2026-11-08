defmodule HeddleUI.Components.Flow.VersionHistory do
  @moduledoc """
  The versions of a flow, newest first: when each was kept, by whom, what it changed
  and whether production runs it. See `HeddleCore.Flows.Versions`.
  """

  use HeddleUI, :html

  attr :open, :boolean, required: true
  attr :versions, :any, required: true, doc: "the stream of versions"
  attr :count, :integer, required: true
  attr :published_id, :any, default: nil
  attr :previewing_id, :any, default: nil
  attr :can_edit, :boolean, default: false

  def version_history(assigns) do
    ~H"""
    <aside
      :if={@open}
      id="version-history"
      class="absolute inset-y-0 right-0 z-30 flex w-full max-w-sm flex-col border-l border-gray-200 bg-white shadow-xl transition dark:border-slate-700 dark:bg-slate-900 dark:shadow-black/50"
    >
      <div class="flex items-center justify-between border-b border-gray-200 px-4 py-3 dark:border-slate-700">
        <h2 class="flex items-center gap-2 text-sm font-semibold text-gray-900 dark:text-white">
          <.icon name="hero-clock" class="size-4 text-primary" /> {gettext("Versions")}
        </h2>
        <.button
          id="version-history-close"
          variant="ghost"
          phx-click="versions_toggle"
          class="p-1"
          title={gettext("Close")}
        >
          <.icon name="hero-x-mark" class="size-5" />
        </.button>
      </div>

      <p class="border-b border-gray-200 px-4 py-2 text-xs leading-5 text-gray-500 dark:border-slate-700 dark:text-gray-400">
        {gettext(
          "The canvas is the draft. Production runs the version marked live, and the draft is kept on its own as you edit."
        )}
      </p>

      <div id="version-list" phx-update="stream" class="min-h-0 flex-1 overflow-y-auto">
        <div
          id="version-list-empty"
          class="hidden px-4 py-10 text-center text-sm text-gray-500 only:block dark:text-gray-400"
        >
          {gettext(
            "No versions yet. Publish the flow, or keep editing: the draft is kept every %{minutes} minutes.",
            minutes: HeddleCore.Flows.Versions.checkpoint_every_minutes()
          )}
        </div>
        <div
          :for={{dom_id, row} <- @versions}
          id={dom_id}
          class={[
            "group border-b border-gray-100 px-4 py-3 transition hover:bg-gray-50 dark:border-slate-800 dark:hover:bg-slate-800/60",
            @previewing_id == row.version.id && "bg-primary/5 dark:bg-primary/10"
          ]}
        >
          <div class="flex items-start justify-between gap-2">
            <div class="min-w-0">
              <div class="flex flex-wrap items-center gap-1.5">
                <span class="font-mono text-sm font-semibold text-gray-900 dark:text-white">
                  v{row.version.number}
                </span>
                <.kind_badge kind={row.version.kind} />
                <span
                  :if={row.version.id == @published_id}
                  id={"version-live-#{row.version.id}"}
                  class="inline-flex items-center gap-1 rounded-full bg-emerald-50 px-2 py-0.5 text-[11px] font-semibold text-emerald-700 dark:bg-emerald-500/15 dark:text-emerald-300"
                >
                  <span class="size-1.5 rounded-full bg-emerald-500"></span> {gettext("Live")}
                </span>
              </div>
              <p class="mt-0.5 text-xs text-gray-500 dark:text-gray-400">
                {Calendar.strftime(row.version.inserted_at, "%Y-%m-%d %H:%M")} UTC
                <span :if={row.version.author}>
                  · {person(row.version.author)}
                </span>
              </p>
            </div>
          </div>

          <p
            :if={row.version.source}
            class="mt-1.5 text-xs text-gray-600 dark:text-gray-300"
          >
            {gettext("Put v%{number} back in production.", number: row.version.source.number)}
          </p>
          <p
            :if={row.version.note}
            class="mt-1.5 whitespace-pre-line break-words text-sm text-gray-700 dark:text-slate-200"
          >
            {row.version.note}
          </p>
          <p class="mt-1.5 text-xs text-gray-600 dark:text-gray-300">{summary(row.summary)}</p>
          <p
            :if={row.contributors != []}
            class="mt-1 flex items-center gap-1 text-xs text-gray-500 dark:text-gray-400"
          >
            <.icon name="hero-pencil-square-micro" class="size-3.5" />
            {gettext("Edited by %{people}", people: Enum.map_join(row.contributors, ", ", &person/1))}
          </p>

          <div class="mt-2 flex flex-wrap items-center gap-1">
            <.button
              id={"version-preview-#{row.version.id}"}
              variant="ghost"
              phx-click="version_preview"
              phx-value-id={row.version.id}
              class="h-7 px-2 text-xs"
            >
              <.icon name="hero-eye-micro" class="size-3.5" /> {gettext("View")}
            </.button>
            <.button
              :if={@can_edit}
              id={"version-restore-#{row.version.id}"}
              variant="ghost"
              phx-click="version_restore"
              phx-value-id={row.version.id}
              data-confirm={
                gettext(
                  "The draft takes what v%{number} had. What the draft has now is kept as a version, and anything not saved on the canvas is lost. Restore it?",
                  number: row.version.number
                )
              }
              class="h-7 px-2 text-xs"
            >
              <.icon name="hero-arrow-uturn-left-micro" class="size-3.5" /> {gettext("Restore")}
            </.button>
            <.button
              :if={@can_edit and row.version.id != @published_id}
              id={"version-publish-#{row.version.id}"}
              variant="ghost"
              phx-click="version_publish"
              phx-value-id={row.version.id}
              data-confirm={
                gettext(
                  "Production runs v%{number} from now on, and the draft stays as it is. Publish it?",
                  number: row.version.number
                )
              }
              class="h-7 px-2 text-xs"
            >
              <.icon name="hero-rocket-launch-micro" class="size-3.5" /> {gettext("Publish this")}
            </.button>
          </div>
        </div>
      </div>
      <p
        :if={@count >= 100}
        class="border-t border-gray-200 px-4 py-2 text-xs text-gray-500 dark:border-slate-700 dark:text-gray-400"
      >
        {gettext("Showing the 100 newest versions.")}
      </p>
    </aside>
    """
  end

  attr :kind, :string, required: true

  defp kind_badge(assigns) do
    ~H"""
    <span class={[
      "rounded-full px-2 py-0.5 text-[11px] font-medium",
      @kind == "publish" && "bg-primary/10 text-primary",
      @kind != "publish" && "bg-gray-100 text-gray-600 dark:bg-slate-800 dark:text-gray-300"
    ]}>
      {kind_label(@kind)}
    </span>
    """
  end

  defp kind_label("publish"), do: gettext("Published")
  defp kind_label("checkpoint"), do: gettext("Draft")
  defp kind_label("run"), do: gettext("Ran")

  @doc false
  def person(%{username: username}) when is_binary(username) and username != "", do: username
  def person(%{email: email}), do: email

  @doc "A line saying what a version changed, from `Heddle.Graph.Diff.summary/1`."
  def summary(summary) when map_size(summary) == 0, do: gettext("Nothing changed in the flow.")

  def summary(summary) do
    [
      count(summary, :nodes_added, &ngettext("%{count} node added", "%{count} nodes added", &1)),
      count(
        summary,
        :nodes_removed,
        &ngettext("%{count} node removed", "%{count} nodes removed", &1)
      ),
      count(
        summary,
        :nodes_changed,
        &ngettext("%{count} node changed", "%{count} nodes changed", &1)
      ),
      count(
        summary,
        :connections_added,
        &ngettext("%{count} connection added", "%{count} connections added", &1)
      ),
      count(
        summary,
        :connections_removed,
        &ngettext("%{count} connection removed", "%{count} connections removed", &1)
      ),
      summary[:connections_reordered] && gettext("connections reordered"),
      count(
        summary,
        :comments_changed,
        &ngettext("%{count} note changed", "%{count} notes changed", &1)
      ),
      only_moved?(summary) && gettext("only moved things around")
    ]
    |> Enum.filter(& &1)
    |> Enum.join(" · ")
  end

  defp count(summary, key, text) do
    case Map.get(summary, key, 0) do
      0 -> nil
      n -> text.(n)
    end
  end

  defp only_moved?(summary), do: Map.keys(summary) == [:nodes_moved]
end
