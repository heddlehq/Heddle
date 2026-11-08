defmodule HeddleUI.Components.Flow.VersionPreview do
  @moduledoc """
  A version drawn on a canvas of its own, over the draft, which stays as it is under
  it. Its nodes show what that version changed from the one before: added, changed,
  and the ones it removed as ghosts where they were.
  """

  use HeddleUI, :html

  alias HeddleUI.Components.Flow.VersionHistory

  attr :preview, :any, required: true
  attr :published_id, :any, default: nil
  attr :can_edit, :boolean, default: false

  def version_preview(assigns) do
    ~H"""
    <div
      :if={@preview}
      id="version-preview-layer"
      class="absolute inset-0 z-20 flex flex-col bg-gray-100 dark:bg-slate-900"
    >
      <div class="flex flex-wrap items-center justify-between gap-3 border-b border-gray-200 bg-white px-4 py-2.5 dark:border-slate-700 dark:bg-slate-800">
        <div class="min-w-0">
          <p class="flex items-center gap-2 text-sm font-semibold text-gray-900 dark:text-white">
            <.icon name="hero-eye" class="size-4 text-primary" />
            {gettext("Viewing v%{number}", number: @preview.version.number)}
            <span
              :if={@preview.version.id == @published_id}
              class="rounded-full bg-emerald-50 px-2 py-0.5 text-[11px] font-semibold text-emerald-700 dark:bg-emerald-500/15 dark:text-emerald-300"
            >
              {gettext("Live")}
            </span>
          </p>
          <p class="mt-0.5 flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-gray-500 dark:text-gray-400">
            <span>
              {Calendar.strftime(@preview.version.inserted_at, "%Y-%m-%d %H:%M")} UTC
              <span :if={@preview.version.author}>
                · {VersionHistory.person(@preview.version.author)}
              </span>
            </span>
            <span class="flex items-center gap-2">
              {gettext("Compared with the version before:")}
              <span class="diff-legend diff-legend-added">{gettext("added")}</span>
              <span class="diff-legend diff-legend-changed">{gettext("changed")}</span>
              <span class="diff-legend diff-legend-removed">{gettext("removed")}</span>
            </span>
          </p>
        </div>
        <div class="flex items-center gap-1">
          <.button
            :if={@can_edit}
            id="version-preview-restore"
            variant="ghost"
            phx-click="version_restore"
            phx-value-id={@preview.version.id}
            data-confirm={
              gettext(
                "The draft takes what v%{number} had. What the draft has now is kept as a version, and anything not saved on the canvas is lost. Restore it?",
                number: @preview.version.number
              )
            }
            class="h-8 px-3"
          >
            <.icon name="hero-arrow-uturn-left" class="size-4" /> {gettext("Restore")}
          </.button>
          <.button
            :if={@can_edit and @preview.version.id != @published_id}
            id="version-preview-publish"
            variant="ghost"
            phx-click="version_publish"
            phx-value-id={@preview.version.id}
            data-confirm={
              gettext(
                "Production runs v%{number} from now on, and the draft stays as it is. Publish it?",
                number: @preview.version.number
              )
            }
            class="h-8 px-3"
          >
            <.icon name="hero-rocket-launch" class="size-4" /> {gettext("Publish this")}
          </.button>
          <.button
            id="version-preview-close"
            variant="outline"
            phx-click="version_preview_close"
            class="h-8 px-3"
          >
            <.icon name="hero-arrow-left" class="size-4" /> {gettext("Back to the draft")}
          </.button>
        </div>
      </div>
      <div
        id={"version-preview-canvas-#{@preview.version.id}"}
        class="relative min-h-0 flex-1"
        phx-hook="VersionPreview"
        phx-update="ignore"
      >
      </div>
    </div>
    """
  end
end
