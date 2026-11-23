defmodule HeddleUI.Components.Modals.CreateIntegrationModal do
  @moduledoc """
  Writes the manifest of a new integration in the Integrations page, checking it as
  it changes. How to write one is in Bobbin's guide, on HexDocs. See
  `HeddleUI.Integrations.create/2`.
  """

  use HeddleUI, :html

  @doc "What the editor starts with: a manifest that works, to change."
  def template do
    """
    # The service: its id can't change once installed.
    id: my_service
    name: My Service
    version: 1.0.0
    description: What My Service does, in one line.
    icon: hero-puzzle-piece
    base_url: https://api.example.com/v1/

    # What a person fills in once, in Credentials.
    credential:
      label: My Service
      fields:
        - name: api_key
          label: API key
          secret: true
      auth:
        type: bearer
        token: "{{credential.api_key}}"

    # Each action becomes a node, with a success and an error output.
    actions:
      - name: Get Item
        description: Returns one item.
        fields:
          - name: id
            label: Item ID
            required: true
        request:
          method: GET
          path: "items/{{fields.id}}"

      - name: Create Item
        description: Creates an item.
        fields:
          - name: title
            label: Title
          - name: notes
            label: Notes
            type: textarea
        request:
          method: POST
          path: items
          body:
            title: "{{fields.title}}"
            notes: "{{fields.notes}}"
        output:
          pick: [id, url]
    """
  end

  @doc "Bobbin's guide to write a manifest."
  def docs_url, do: "https://hexdocs.pm/bobbin/manifest.html"

  attr :form, :any, required: true
  attr :check, :any, required: true, doc: "`{:ok, manifest}` or `{:error, problems}`"

  def create_integration_modal(assigns) do
    assigns = assign(assigns, :docs_url, docs_url())

    ~H"""
    <div
      id="create-integration-modal"
      class="fixed inset-0 z-[110] flex items-center justify-center bg-black/60 p-3 backdrop-blur-sm sm:p-6"
      phx-window-keydown="close_create"
      phx-key="Escape"
    >
      <div class="flex h-full max-h-[56rem] w-full max-w-5xl flex-col overflow-hidden rounded-xl border border-gray-200 bg-white shadow-2xl dark:border-slate-700 dark:bg-slate-900">
        <div class="flex items-center justify-between gap-4 border-b border-gray-200 px-5 py-3.5 dark:border-slate-800">
          <div class="flex min-w-0 items-center gap-3">
            <span class="rounded-lg bg-primary/10 p-1.5 text-primary">
              <.icon name="hero-puzzle-piece" class="size-5" />
            </span>
            <div class="min-w-0">
              <h3 class="text-base font-semibold text-gray-900 dark:text-white">
                {gettext("Create integration")}
              </h3>
              <p class="truncate text-xs text-gray-500 dark:text-gray-400">
                {gettext(
                  "A manifest in YAML: a service's credential and its actions as HTTP requests. Each action becomes a node."
                )}
              </p>
            </div>
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
          <div class="flex min-h-0 flex-1 flex-col lg:flex-row">
            <div class="flex min-h-[22rem] min-w-0 flex-1 flex-col">
              <div
                id="create-integration-editor"
                phx-hook="ManifestEditor"
                phx-update="ignore"
                class="relative min-h-0 flex-1"
              >
                <textarea
                  id="create-integration-manifest"
                  name={@form[:manifest].name}
                  phx-debounce="300"
                  spellcheck="false"
                  autocomplete="off"
                  aria-label={gettext("Manifest")}
                  class="absolute inset-0 h-full w-full resize-none border-0 bg-white p-4 font-mono text-[13px] leading-relaxed text-gray-900 outline-none dark:bg-slate-950 dark:text-slate-100"
                >{Phoenix.HTML.Form.normalize_value("textarea", @form[:manifest].value)}</textarea>
                <div data-monaco class="absolute inset-0 hidden"></div>
              </div>
              <.check_result check={@check} />
            </div>
          </div>

          <div class="flex flex-col-reverse gap-3 border-t border-gray-200 px-5 py-3 sm:flex-row sm:items-center sm:justify-between dark:border-slate-800">
            <div class="flex flex-col gap-1">
              <a
                id="create-integration-docs"
                href={@docs_url}
                target="_blank"
                rel="noopener"
                class="inline-flex items-center gap-1 text-sm font-medium text-primary transition hover:opacity-80"
              >
                <.icon name="hero-book-open" class="size-4" />
                {gettext("How to write a manifest")}
                <.icon name="hero-arrow-top-right-on-square-mini" class="size-3.5" />
              </a>
              <p class="text-xs text-gray-500 dark:text-gray-400">
                {gettext(
                  "It's installed in this workspace, and other workspaces of the instance can install it too."
                )}
              </p>
            </div>
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
      class="flex items-center gap-3 border-t border-emerald-500/30 bg-emerald-500/5 px-4 py-2.5"
    >
      <span class="flex size-8 shrink-0 items-center justify-center rounded-lg bg-violet-500/15 text-violet-700 dark:text-violet-300">
        <.icon name={@manifest.icon || "hero-puzzle-piece"} class="size-4" />
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
      class="max-h-36 overflow-y-auto border-t border-red-500/30 bg-red-500/5 px-4 py-2.5"
    >
      <p class="flex items-center gap-1.5 text-sm font-medium text-red-700 dark:text-red-300">
        <.icon name="hero-exclamation-triangle-mini" class="size-4" />
        {ngettext("1 thing to fix", "%{count} things to fix", length(@problems))}
      </p>
      <ul class="mt-1 space-y-0.5 pl-6 text-xs text-red-700/90 dark:text-red-300/90">
        <li :for={problem <- @problems} class="list-disc font-mono">{problem}</li>
      </ul>
    </div>
    """
  end
end
