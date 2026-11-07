defmodule HeddleUI.Components.Modals.WebhookTestModal do
  @moduledoc """
  Asks for the request to send when testing a flow that starts at a Webhook node.
  """

  use HeddleUI, :html

  attr :open, :boolean, required: true
  attr :form, :any, required: true
  attr :error, :string, default: nil
  attr :fields, :list, default: []

  def webhook_test_modal(assigns) do
    ~H"""
    <div
      :if={@open}
      id="webhook-test-modal"
      class="fixed inset-0 z-[110] flex items-center justify-center bg-black/60 p-4 backdrop-blur-sm"
    >
      <div class="flex w-full max-w-xl flex-col rounded-lg border border-gray-200 bg-white shadow-2xl dark:border-slate-700 dark:bg-slate-800">
        <div class="flex items-center justify-between border-b border-gray-200 px-6 py-4 dark:border-slate-700">
          <h3 class="flex items-center gap-2 text-lg font-semibold text-gray-900 dark:text-slate-100">
            <span class="rounded bg-primary/10 p-1 text-primary">
              <.icon name="hero-bolt" class="size-5" />
            </span>
            {gettext("Test the webhook")}
          </h3>
          <.button variant="ghost" phx-click="close_webhook_test" class="p-1">
            <.icon name="hero-x-mark" class="size-6" />
          </.button>
        </div>

        <.form for={@form} id="webhook-test-form" phx-submit="run_webhook_test" class="space-y-4 p-6">
          <p class="text-sm text-gray-500 dark:text-gray-400">
            {gettext("The flow runs as if this request had reached the Webhook node.")}
          </p>
          <.method_picker field={@form[:method]} />
          <.body_editor field={@form[:body]} fields={@fields} />
          <p :if={@error} id="webhook-test-error" class="text-sm text-error">{@error}</p>
          <div class="flex justify-end gap-2">
            <.button type="button" variant="ghost" phx-click="close_webhook_test">
              {gettext("Cancel")}
            </.button>
            <.button id="webhook-test-run" type="submit" variant="primary">
              {gettext("Run")}
            </.button>
          </div>
        </.form>
      </div>
    </div>
    """
  end

  attr :field, Phoenix.HTML.FormField, required: true

  defp method_picker(assigns) do
    ~H"""
    <div
      id="webhook-test-method"
      role="radiogroup"
      aria-label={gettext("Method")}
      class="inline-flex rounded-lg border border-gray-200 bg-gray-50 p-0.5 dark:border-slate-700 dark:bg-slate-900"
    >
      <label :for={method <- ~w(POST GET PUT DELETE)} class="cursor-pointer">
        <input
          type="radio"
          name={@field.name}
          value={method}
          checked={@field.value == method}
          class="peer sr-only"
        />
        <span class="block rounded-md px-3 py-1 font-mono text-xs font-medium text-gray-500 transition peer-checked:bg-primary peer-checked:text-primary-content peer-focus-visible:ring-2 peer-focus-visible:ring-primary dark:text-gray-400">
          {method}
        </span>
      </label>
    </div>
    """
  end

  attr :field, Phoenix.HTML.FormField, required: true
  attr :fields, :list, required: true

  # The hook owns what is inside, and both tabs edit the value of the hidden input.
  defp body_editor(assigns) do
    ~H"""
    <div
      id="webhook-body-editor"
      phx-hook="WebhookBody"
      phx-update="ignore"
      data-fields={Jason.encode!(@fields)}
      data-name-label={gettext("Field")}
      data-value-label={gettext("Value")}
      data-remove-label={gettext("Remove")}
      data-invalid={gettext("The body isn't valid JSON.")}
    >
      <input type="hidden" id={@field.id} name={@field.name} value={@field.value} />

      <div class="flex items-center border-b border-gray-200 dark:border-slate-700">
        <button type="button" data-tab="params">{gettext("Parameters")}</button>
        <button type="button" data-tab="json">JSON</button>
        <button
          type="button"
          data-format
          class="ml-auto flex items-center gap-1 px-2 py-1 text-xs font-medium text-gray-500 transition hover:text-primary dark:text-gray-400"
        >
          <.icon name="hero-sparkles" class="size-3.5" />
          {gettext("Format")}
        </button>
      </div>

      <div data-pane="params" class="hidden space-y-2 pt-3">
        <div data-rows class="max-h-64 space-y-1.5 overflow-y-auto"></div>
        <button
          type="button"
          data-add
          class="flex items-center gap-1 text-sm font-medium text-primary transition hover:opacity-80"
        >
          <.icon name="hero-plus" class="size-4" />
          {gettext("Add field")}
        </button>
      </div>

      <div
        data-pane="json"
        class="hidden relative mt-3 h-64 overflow-hidden rounded-md border border-gray-200 dark:border-slate-700"
      >
        <div data-monaco class="absolute inset-0"></div>
        <p data-fallback class="p-3 text-sm text-gray-500 dark:text-gray-400">
          {gettext("Loading the editor...")}
        </p>
      </div>

      <p data-error class="mt-2 hidden text-sm text-error"></p>
    </div>
    """
  end
end
