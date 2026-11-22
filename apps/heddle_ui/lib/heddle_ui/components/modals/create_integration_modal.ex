defmodule HeddleUI.Components.Modals.CreateIntegrationModal do
  @moduledoc """
  Writes the manifest of a new integration in the Integrations page, checking it as
  it changes. See `HeddleUI.Integrations.create/2`.
  """

  use HeddleUI, :html

  @doc "What the editor starts with: a manifest that works, to change."
  def template do
    """
    id: acme_crm
    name: Acme CRM
    version: 1.0.0
    description: Contacts and deals in Acme CRM.
    icon: hero-puzzle-piece
    base_url: https://api.acme.example/v1/

    credential:
      label: Acme CRM
      fields:
        - name: api_key
          label: API key
          secret: true
      auth:
        type: bearer
        token: "{{credential.api_key}}"

    actions:
      - name: Get Contact
        description: Returns one contact.
        fields:
          - name: id
            label: Contact ID
        request:
          method: GET
          path: "contacts/{{fields.id}}"

      - name: Create Contact
        description: Creates a contact.
        fields:
          - name: email
            label: Email
          - name: name
            label: Name
        request:
          method: POST
          path: contacts
          body:
            email: "{{fields.email}}"
            name: "{{fields.name}}"
    """
  end

  attr :form, :any, required: true
  attr :check, :any, required: true, doc: "`{:ok, manifest}` or `{:error, problems}`"

  def create_integration_modal(assigns) do
    ~H"""
    <div
      id="create-integration-modal"
      class="fixed inset-0 z-[110] flex items-center justify-center bg-black/60 p-4 backdrop-blur-sm"
      phx-window-keydown="close_create"
      phx-key="Escape"
    >
      <div class="flex max-h-full w-full max-w-3xl flex-col rounded-xl border border-gray-200 bg-white shadow-2xl dark:border-slate-700 dark:bg-slate-900">
        <div class="flex items-start justify-between gap-4 border-b border-gray-200 px-6 py-4 dark:border-slate-800">
          <div>
            <h3 class="flex items-center gap-2 text-lg font-semibold text-gray-900 dark:text-white">
              <span class="rounded-lg bg-primary/10 p-1.5 text-primary">
                <.icon name="hero-puzzle-piece" class="size-5" />
              </span>
              {gettext("Create integration")}
            </h3>
            <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
              {gettext(
                "Describe a service's credential and its actions as HTTP requests. Each action becomes a node."
              )}
            </p>
          </div>
          <.button
            id="create-integration-close"
            variant="ghost"
            phx-click="close_create"
            class="p-1"
            aria-label={gettext("Close")}
          >
            <.icon name="hero-x-mark" class="size-6" />
          </.button>
        </div>

        <.form
          for={@form}
          id="create-integration-form"
          phx-change="check_manifest"
          phx-submit="create_integration"
          class="flex min-h-0 flex-1 flex-col"
        >
          <div class="min-h-0 flex-1 overflow-y-auto px-6 py-4">
            <textarea
              id="create-integration-manifest"
              name={@form[:manifest].name}
              phx-debounce="300"
              spellcheck="false"
              autocomplete="off"
              aria-label={gettext("Manifest")}
              class="h-[26rem] w-full resize-y rounded-lg border border-gray-200 bg-gray-50 p-4 font-mono text-[13px] leading-relaxed text-gray-900 outline-none transition focus:border-primary focus:ring-2 focus:ring-primary/20 dark:border-slate-700 dark:bg-slate-950 dark:text-slate-100"
            >{Phoenix.HTML.Form.normalize_value("textarea", @form[:manifest].value)}</textarea>

            <.check_result check={@check} />
          </div>

          <div class="flex flex-col-reverse gap-3 border-t border-gray-200 px-6 py-4 sm:flex-row sm:items-center sm:justify-between dark:border-slate-800">
            <a
              href="https://github.com/heddlehq/Bobbin#integrations-without-code"
              target="_blank"
              rel="noopener"
              class="inline-flex items-center gap-1 text-sm font-medium text-primary transition hover:opacity-80"
            >
              <.icon name="hero-book-open" class="size-4" />
              {gettext("How to write a manifest")}
            </a>
            <div class="flex justify-end gap-2">
              <.button type="button" variant="ghost" phx-click="close_create">
                {gettext("Cancel")}
              </.button>
              <.button
                id="create-integration-submit"
                type="submit"
                variant="primary"
                disabled={not match?({:ok, _manifest}, @check)}
                phx-disable-with={gettext("Creating...")}
              >
                {gettext("Create and install")}
              </.button>
            </div>
          </div>
        </.form>
      </div>
    </div>
    """
  end

  attr :check, :any, required: true

  defp check_result(%{check: {:ok, manifest}} = assigns) do
    assigns = assign(assigns, :manifest, manifest)

    ~H"""
    <div
      id="create-integration-valid"
      class="mt-3 flex items-center gap-3 rounded-lg border border-emerald-500/30 bg-emerald-500/5 px-4 py-3"
    >
      <span class="flex size-9 shrink-0 items-center justify-center rounded-lg bg-violet-500/15 text-violet-700 dark:text-violet-300">
        <.icon name={@manifest.icon || "hero-puzzle-piece"} class="size-5" />
      </span>
      <div class="min-w-0 flex-1">
        <p class="truncate text-sm font-semibold text-gray-900 dark:text-white">
          {@manifest.name}
          <span class="font-normal text-gray-500 dark:text-gray-400">· v{@manifest.version}</span>
        </p>
        <p class="truncate text-xs text-gray-500 dark:text-gray-400">
          {ngettext("1 action", "%{count} actions", length(@manifest.actions))}<span :if={
            @manifest.triggers != []
          }>
            · {ngettext("1 trigger", "%{count} triggers", length(@manifest.triggers))}
          </span> · {Enum.map_join(
            @manifest.actions ++ @manifest.triggers,
            ", ",
            & &1.name
          )}
        </p>
      </div>
      <.icon
        name="hero-check-circle-solid"
        class="size-5 shrink-0 text-emerald-600 dark:text-emerald-400"
      />
    </div>
    """
  end

  defp check_result(%{check: {:error, problems}} = assigns) do
    assigns = assign(assigns, :problems, problems)

    ~H"""
    <div
      id="create-integration-problems"
      class="mt-3 rounded-lg border border-red-500/30 bg-red-500/5 px-4 py-3"
    >
      <p class="flex items-center gap-1.5 text-sm font-medium text-red-700 dark:text-red-300">
        <.icon name="hero-exclamation-triangle-mini" class="size-4" />
        {ngettext("1 thing to fix", "%{count} things to fix", length(@problems))}
      </p>
      <ul class="mt-1.5 space-y-0.5 pl-6 text-xs text-red-700/90 dark:text-red-300/90">
        <li :for={problem <- @problems} class="list-disc font-mono">{problem}</li>
      </ul>
    </div>
    """
  end
end
