defmodule HeddleUI.Components.Modals.FlowSettingsModal do
  @moduledoc """
  The settings of a flow that aren't on its canvas: for now, the flow that runs when a
  run of it fails.
  """

  use HeddleUI, :html

  attr :open, :boolean, required: true
  attr :form, :any, required: true
  attr :options, :list, default: []

  def flow_settings_modal(assigns) do
    ~H"""
    <div
      :if={@open}
      id="flow-settings-modal"
      class="fixed inset-0 z-[110] flex items-center justify-center bg-black/60 p-4 backdrop-blur-sm"
      phx-window-keydown="close_flow_settings"
      phx-key="Escape"
    >
      <div
        class="flex w-full max-w-lg flex-col rounded-lg border border-gray-200 bg-white shadow-2xl dark:border-slate-700 dark:bg-slate-800"
        phx-click-away="close_flow_settings"
      >
        <div class="flex items-center justify-between border-b border-gray-200 px-6 py-4 dark:border-slate-700">
          <h3 class="flex items-center gap-2 text-lg font-semibold text-gray-900 dark:text-slate-100">
            <span class="rounded bg-primary/10 p-1 text-primary">
              <.icon name="hero-cog-6-tooth" class="size-5" />
            </span>
            {gettext("Flow settings")}
          </h3>
          <.button variant="ghost" phx-click="close_flow_settings" class="p-1">
            <.icon name="hero-x-mark" class="size-6" />
          </.button>
        </div>

        <.form
          for={@form}
          id="flow-settings-form"
          phx-submit="save_flow_settings"
          class="space-y-4 p-6"
        >
          <div>
            <.input
              field={@form[:error_flow_id]}
              type="select"
              label={gettext("Error flow")}
              prompt={gettext("None")}
              options={@options}
            />
            <p class="mt-2 text-sm leading-6 text-gray-500 dark:text-gray-400">
              {gettext(
                "When a run of this flow fails, the flow picked here runs, from its Error Trigger node, with the error and a link to the run."
              )}
            </p>
            <p
              :if={@options == []}
              id="flow-settings-no-flows"
              class="mt-2 text-sm text-gray-500 dark:text-gray-400"
            >
              {gettext("Make another flow first, starting with an Error Trigger.")}
            </p>
          </div>
          <div class="flex justify-end gap-2">
            <.button type="button" variant="ghost" phx-click="close_flow_settings">
              {gettext("Cancel")}
            </.button>
            <.button id="flow-settings-save" type="submit" variant="primary">
              {gettext("Save")}
            </.button>
          </div>
        </.form>
      </div>
    </div>
    """
  end
end
