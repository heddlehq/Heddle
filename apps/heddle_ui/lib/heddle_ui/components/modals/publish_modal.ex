defmodule HeddleUI.Components.Modals.PublishModal do
  @moduledoc """
  Publishing the draft: what production runs from then on, with a note saying why.
  See `HeddleCore.Flows.Versions`.
  """

  use HeddleUI, :html

  attr :open, :boolean, required: true
  attr :form, :any, required: true
  attr :status, :atom, required: true, doc: "`:unpublished`, `:changed` or `:published`"

  def publish_modal(assigns) do
    ~H"""
    <div
      :if={@open}
      id="publish-modal"
      class="fixed inset-0 z-[110] flex items-center justify-center bg-black/60 p-4 backdrop-blur-sm"
      phx-window-keydown="close_publish"
      phx-key="Escape"
    >
      <div
        class="flex w-full max-w-lg flex-col rounded-lg border border-gray-200 bg-white shadow-2xl dark:border-slate-700 dark:bg-slate-800"
        phx-click-away="close_publish"
      >
        <div class="flex items-center justify-between border-b border-gray-200 px-6 py-4 dark:border-slate-700">
          <h3 class="flex items-center gap-2 text-lg font-semibold text-gray-900 dark:text-slate-100">
            <span class="rounded bg-primary/10 p-1 text-primary">
              <.icon name="hero-rocket-launch" class="size-5" />
            </span>
            {gettext("Publish")}
          </h3>
          <.button variant="ghost" phx-click="close_publish" class="p-1">
            <.icon name="hero-x-mark" class="size-6" />
          </.button>
        </div>

        <.form for={@form} id="publish-form" phx-submit="publish" class="space-y-4 p-6">
          <p class="text-sm leading-6 text-gray-600 dark:text-gray-300">
            <%= if @status == :unpublished do %>
              {gettext(
                "This flow isn't in production yet. Once published, its webhooks answer, its schedules start, and the API and other flows run it."
              )}
            <% else %>
              {gettext(
                "What is on the canvas now takes the place of what production runs. Runs already going keep the version they started with."
              )}
            <% end %>
          </p>
          <p
            :if={@status == :published}
            id="publish-nothing-new"
            class="rounded-lg bg-gray-50 px-3 py-2 text-sm text-gray-600 dark:bg-slate-900 dark:text-gray-300"
          >
            {gettext(
              "Production already runs what the canvas has. Publishing keeps it as a version anyway."
            )}
          </p>
          <.input
            field={@form[:note]}
            type="textarea"
            label={gettext("What changed (optional)")}
            placeholder={gettext("e.g. Retry the payment call twice")}
            maxlength="500"
            rows="3"
          />
          <div class="flex justify-end gap-2">
            <.button type="button" variant="ghost" phx-click="close_publish">
              {gettext("Cancel")}
            </.button>
            <.button
              id="publish-submit"
              type="submit"
              variant="primary"
              phx-disable-with={gettext("Publishing...")}
            >
              <.icon name="hero-rocket-launch" class="size-4" /> {gettext("Publish")}
            </.button>
          </div>
        </.form>
      </div>
    </div>
    """
  end
end
