defmodule HeddleUI.SpoolLive.Index do
  @moduledoc """
  The Spool tables of the workspace, and a new one for editors. See `HeddleCore.Spool`.
  """

  use HeddleUI, :live_view

  on_mount {HeddleUI.UserAuth, {:require_workspace, :view}}

  alias HeddleCore.{Spool, Workspaces}
  alias HeddleCore.Spool.Table

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    {:ok,
     socket
     |> assign(:page_title, "Spool")
     |> assign(:can_edit, Workspaces.can?(scope, :edit))
     |> assign(:form, to_form(Spool.change_table(%Table{}), as: :table))
     |> load_tables()}
  end

  defp load_tables(socket) do
    tables = Spool.list_tables(socket.assigns.current_scope)

    socket
    |> assign(:empty?, tables == [])
    |> stream(:tables, tables, reset: true)
  end

  @impl true
  def handle_event("validate", %{"table" => params}, socket) do
    changeset = Spool.change_table(%Table{}, params)
    {:noreply, assign(socket, :form, to_form(changeset, as: :table, action: :validate))}
  end

  def handle_event("create", %{"table" => params}, socket) do
    case Spool.create_table(socket.assigns.current_scope, params) do
      {:ok, table} ->
        {:noreply, push_navigate(socket, to: ~p"/spool/#{table.id}?tab=columns")}

      {:error, :forbidden} ->
        {:noreply,
         put_flash(socket, :error, gettext("Your role lets you see tables, not create them."))}

      {:error, {:limit, max}} ->
        {:noreply,
         put_flash(socket, :error, gettext("A workspace keeps up to %{max} tables.", max: max))}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :table, action: :insert))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 md:p-8 w-full max-w-7xl mx-auto space-y-8">
      <div class="flex flex-col gap-4 md:flex-row md:items-end md:justify-between">
        <div>
          <h1 class="flex items-center gap-2 text-2xl font-bold text-gray-900 dark:text-white">
            <.icon name="hero-circle-stack" class="size-6 text-primary" /> Spool
          </h1>
          <p class="mt-1 max-w-2xl text-sm text-gray-500 dark:text-gray-400">
            {gettext(
              "Tables this workspace keeps inside Heddle, with nothing to set up. Flows read and write them with the Spool nodes, and a form can save its answers in one."
            )}
          </p>
        </div>

        <.form
          :if={@can_edit}
          for={@form}
          id="spool-table-form"
          phx-change="validate"
          phx-submit="create"
          class="flex w-full items-end gap-2 md:w-auto"
        >
          <div class="min-w-0 flex-1 md:w-64">
            <.input
              field={@form[:name]}
              type="text"
              placeholder={gettext("New table name")}
              autocomplete="off"
            />
          </div>
          <.button
            id="spool-table-create"
            type="submit"
            variant="primary"
            size="field"
            class="mb-3"
          >
            <.icon name="hero-plus" class="size-4" /> {gettext("Create")}
          </.button>
        </.form>
      </div>

      <div
        :if={@empty?}
        id="spool-empty"
        class="flex flex-col items-center gap-3 rounded-xl border border-dashed border-gray-300 px-6 py-16 text-center dark:border-slate-700"
      >
        <span class="flex size-12 items-center justify-center rounded-full bg-primary/10 text-primary">
          <.icon name="hero-circle-stack" class="size-6" />
        </span>
        <p class="text-sm font-medium text-gray-900 dark:text-white">{gettext("No tables yet")}</p>
        <p class="max-w-sm text-sm text-gray-500 dark:text-gray-400">
          {gettext(
            "Create one here, or from a Form Trigger to keep its answers. Each table has typed columns, and its rows live in Heddle's own database."
          )}
        </p>
      </div>

      <div id="spool-tables" phx-update="stream" class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <.link
          :for={{id, table} <- @streams.tables}
          id={id}
          navigate={~p"/spool/#{table.id}"}
          class="group flex flex-col gap-4 rounded-xl border border-gray-200 bg-white p-5 shadow-sm transition-all duration-150 hover:-translate-y-0.5 hover:border-primary/40 hover:shadow-md dark:border-slate-800 dark:bg-slate-900 dark:hover:border-primary/40"
        >
          <div class="flex items-start justify-between gap-3">
            <div class="flex min-w-0 items-center gap-3">
              <span class="flex size-9 shrink-0 items-center justify-center rounded-lg bg-primary/10 text-primary">
                <.icon name="hero-table-cells" class="size-5" />
              </span>
              <p class="truncate font-semibold text-gray-900 dark:text-white">{table.name}</p>
            </div>
            <.icon
              name="hero-arrow-right"
              class="size-4 shrink-0 text-gray-400 opacity-0 transition-all group-hover:translate-x-0.5 group-hover:opacity-100"
            />
          </div>
          <div class="flex flex-wrap gap-1.5">
            <span
              :for={column <- Enum.take(table.columns, 5)}
              class="rounded-md bg-gray-100 px-2 py-0.5 font-mono text-[11px] text-gray-600 dark:bg-slate-800 dark:text-gray-300"
            >
              {column["name"]}
            </span>
            <span
              :if={length(table.columns) > 5}
              class="px-1 py-0.5 text-[11px] text-gray-500 dark:text-gray-400"
            >
              +{length(table.columns) - 5}
            </span>
          </div>
          <p class="mt-auto text-xs text-gray-500 dark:text-gray-400">
            {ngettext("1 row", "%{count} rows", table.row_count)} · {ngettext(
              "1 column",
              "%{count} columns",
              length(table.columns)
            )}
          </p>
        </.link>
      </div>
    </div>
    """
  end
end
