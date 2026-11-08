defmodule HeddleUI.SpoolLive.Table do
  @moduledoc """
  One Spool table: its rows, to search, add, change and delete, and its columns, to
  rename, retype, add and remove. Viewers only look. See `HeddleCore.Spool`.

  The tab, page and search live in the URL, so a link opens the same view.
  """

  use HeddleUI, :live_view

  on_mount {HeddleUI.UserAuth, {:require_workspace, :view}}

  import HeddleUI.SpoolLive.Components

  alias HeddleCore.{Spool, Workspaces}
  alias HeddleCore.Spool.Column

  @per_page 50

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope

    case Spool.get_table(scope, id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, gettext("This table doesn't exist."))
         |> push_navigate(to: ~p"/spool")}

      table ->
        {:ok,
         socket
         |> assign(:page_title, table.name)
         |> assign(:can_edit, Workspaces.can?(scope, :edit))
         |> assign(:can_manage, Workspaces.can?(scope, :manage))
         |> assign(:column_types, Column.types())
         |> assign(:editing_row, nil)
         |> assign(:row_error, nil)
         |> stream_configure(:rows, dom_id: &"spool-row-#{&1["id"]}")
         |> assign_table(table)}
    end
  end

  defp assign_table(socket, table) do
    socket
    |> assign(:table, table)
    |> assign(:columns_draft, table.columns)
    |> assign(:columns_form, columns_form(table.name, table.columns))
    |> assign(:columns_error, nil)
  end

  @impl true
  def handle_params(params, _uri, socket) do
    tab = if params["tab"] == "columns", do: "columns", else: "rows"
    page = params |> Map.get("page", "1") |> parse_page()
    search = Map.get(params, "q", "")

    {:noreply,
     socket
     |> assign(tab: tab, page: page, search: search)
     |> load_rows()}
  end

  defp parse_page(page) do
    case Integer.parse(to_string(page)) do
      {page, ""} when page > 0 -> page
      _other -> 1
    end
  end

  defp load_rows(socket) do
    %{current_scope: scope, table: table, page: page, search: search} = socket.assigns

    %{rows: rows, total: total} =
      Spool.list_rows(scope, table, page: page, per_page: @per_page, search: search)

    socket
    |> assign(:total, total)
    |> assign(:pages, max(1, ceil(total / @per_page)))
    |> assign(:empty?, rows == [])
    |> stream(:rows, rows, reset: true)
  end

  defp table_path(socket, overrides) do
    params =
      %{"tab" => socket.assigns.tab, "page" => socket.assigns.page, "q" => socket.assigns.search}
      |> Map.merge(overrides)
      |> Enum.reject(fn {key, value} ->
        value in ["", nil] or {key, value} in [{"tab", "rows"}, {"page", 1}]
      end)

    ~p"/spool/#{socket.assigns.table.id}?#{params}"
  end

  ## Rows

  @impl true
  def handle_event("search", %{"q" => q}, socket) do
    {:noreply, push_patch(socket, to: table_path(socket, %{"q" => q, "page" => 1}))}
  end

  def handle_event("new_row", _params, socket) do
    {:noreply, assign(socket, editing_row: %{}, row_error: nil)}
  end

  def handle_event("edit_row", %{"id" => id}, socket) do
    row = find_row(socket, id)
    {:noreply, assign(socket, editing_row: row, row_error: nil)}
  end

  def handle_event("close_row", _params, socket) do
    {:noreply, assign(socket, editing_row: nil, row_error: nil)}
  end

  def handle_event("save_row", %{"row" => params}, socket) do
    %{current_scope: scope, table: table, editing_row: row} = socket.assigns

    with {:ok, values} <- row_values(table.columns, params),
         {:ok, _row} <- save_row(scope, table, row, values) do
      {:noreply,
       socket
       |> assign(editing_row: nil, row_error: nil)
       |> put_flash(:info, gettext("Row saved."))
       |> load_rows()}
    else
      {:error, :forbidden} -> {:noreply, forbidden(socket)}
      {:error, message} -> {:noreply, assign(socket, :row_error, message)}
    end
  end

  def handle_event("delete_row", %{"id" => id}, socket) do
    case Spool.delete_row(socket.assigns.current_scope, socket.assigns.table, id) do
      :ok ->
        {:noreply,
         socket
         |> assign(:editing_row, nil)
         |> put_flash(:info, gettext("Row deleted."))
         |> load_rows()}

      {:error, :forbidden} ->
        {:noreply, forbidden(socket)}

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  ## Columns

  def handle_event("columns_change", %{"table" => params}, socket) do
    columns = draft_columns(params)

    {:noreply,
     assign(socket, columns_draft: columns, columns_form: columns_form(params["name"], columns))}
  end

  def handle_event("add_column", _params, socket) do
    columns = socket.assigns.columns_draft ++ [%{"id" => "", "name" => "", "type" => "text"}]

    {:noreply,
     assign(socket,
       columns_draft: columns,
       columns_form: columns_form(socket.assigns.columns_form[:name].value, columns)
     )}
  end

  def handle_event("remove_column", %{"index" => index}, socket) do
    columns = List.delete_at(socket.assigns.columns_draft, String.to_integer(index))

    {:noreply,
     assign(socket,
       columns_draft: columns,
       columns_form: columns_form(socket.assigns.columns_form[:name].value, columns)
     )}
  end

  def handle_event("save_columns", %{"table" => params}, socket) do
    attrs = %{"name" => params["name"], "columns" => draft_columns(params)}

    case Spool.update_table(socket.assigns.current_scope, socket.assigns.table, attrs) do
      {:ok, table} ->
        {:noreply,
         socket
         |> assign_table(table)
         |> assign(:page_title, table.name)
         |> put_flash(:info, gettext("Table saved."))
         |> load_rows()}

      {:error, :forbidden} ->
        {:noreply, forbidden(socket)}

      {:error, changeset} ->
        {:noreply, assign(socket, :columns_error, changeset_message(changeset))}
    end
  end

  def handle_event("reset_columns", _params, socket) do
    {:noreply, assign_table(socket, socket.assigns.table)}
  end

  def handle_event("delete_table", _params, socket) do
    case Spool.delete_table(socket.assigns.current_scope, socket.assigns.table) do
      {:ok, _table} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Table deleted."))
         |> push_navigate(to: ~p"/spool")}

      {:error, _reason} ->
        {:noreply,
         put_flash(socket, :error, gettext("Only admins of the workspace delete tables."))}
    end
  end

  defp forbidden(socket) do
    put_flash(socket, :error, gettext("Your role lets you see this table, not change it."))
  end

  defp find_row(socket, id) do
    %{rows: rows} =
      Spool.list_rows(socket.assigns.current_scope, socket.assigns.table,
        page: socket.assigns.page,
        per_page: @per_page,
        search: socket.assigns.search
      )

    Enum.find(rows, &(to_string(&1["id"]) == to_string(id)))
  end

  defp save_row(scope, table, row, values) when row == %{},
    do: Spool.insert_row(scope, table, values)

  defp save_row(scope, table, row, values), do: Spool.update_row(scope, table, row["id"], values)

  # What the form sends is text: an empty field clears its column, and a json column
  # takes JSON.
  defp row_values(columns, params) do
    Enum.reduce_while(columns, {:ok, %{}}, fn column, {:ok, values} ->
      raw = params[column["id"]]

      case parse_field(column, raw) do
        {:ok, value} -> {:cont, {:ok, Map.put(values, column["name"], value)}}
        {:error, message} -> {:halt, {:error, message}}
      end
    end)
  end

  defp parse_field(_column, nil), do: {:ok, nil}
  defp parse_field(_column, ""), do: {:ok, nil}

  defp parse_field(%{"type" => "json"} = column, raw) do
    case Jason.decode(raw) do
      {:ok, value} ->
        {:ok, value}

      {:error, _reason} ->
        {:error, gettext("%{column} isn't valid JSON.", column: column["name"])}
    end
  end

  defp parse_field(_column, raw), do: {:ok, raw}

  defp draft_columns(params) do
    params
    |> Map.get("columns", %{})
    |> Enum.sort_by(fn {index, _column} -> String.to_integer(index) end)
    |> Enum.map(fn {_index, column} ->
      %{
        "id" => column["id"] || "",
        "name" => column["name"] || "",
        "type" => column["type"] || "text"
      }
    end)
  end

  defp columns_form(name, columns) do
    columns =
      columns
      |> Enum.with_index()
      |> Map.new(fn {column, index} -> {to_string(index), column} end)

    to_form(%{"name" => name, "columns" => columns}, as: :table)
  end

  defp changeset_message(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map_join(". ", fn {field, messages} ->
      "#{field_label(field)}: #{Enum.join(messages, ", ")}"
    end)
  end

  defp field_label(:name), do: gettext("Name")
  defp field_label(:columns), do: gettext("Columns")
  defp field_label(field), do: to_string(field)

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 md:p-8 w-full max-w-7xl mx-auto space-y-6">
      <div class="flex flex-col gap-4 md:flex-row md:items-start md:justify-between">
        <div class="min-w-0">
          <.link
            navigate={~p"/spool"}
            class="inline-flex items-center gap-1 text-sm text-gray-500 transition-colors hover:text-primary dark:text-gray-400"
          >
            <.icon name="hero-arrow-left-mini" class="size-4" /> Spool
          </.link>
          <h1
            id="spool-table-name"
            class="mt-1 truncate text-2xl font-bold text-gray-900 dark:text-white"
          >
            {@table.name}
          </h1>
          <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
            {ngettext("1 row", "%{count} rows", @total)} · {gettext("Use it in flows as")}
            <code class="rounded bg-gray-100 px-1.5 py-0.5 font-mono text-xs text-gray-700 dark:bg-slate-800 dark:text-gray-300">
              {@table.name}
            </code>
          </p>
        </div>
        <div class="flex shrink-0 gap-2">
          <.button
            id="spool-export"
            href={~p"/spool/#{@table.id}/export"}
            variant="ghost"
            class="border border-gray-200 dark:border-slate-700"
          >
            <.icon name="hero-arrow-down-tray" class="size-4" /> {gettext("Export CSV")}
          </.button>
          <.button
            :if={@can_manage}
            id="spool-delete-table"
            variant="ghost"
            phx-click="delete_table"
            data-confirm={gettext("Delete this table and all its rows? Flows that use it will fail.")}
            class="text-rose-600 hover:bg-rose-50 dark:text-rose-400 dark:hover:bg-rose-900/20"
          >
            <.icon name="hero-trash" class="size-4" /> {gettext("Delete")}
          </.button>
        </div>
      </div>

      <div class="flex gap-1 border-b border-gray-200 dark:border-slate-800" role="tablist">
        <.tab
          id="spool-tab-rows"
          active={@tab == "rows"}
          patch={table_path(assigns_socket(assigns), %{"tab" => "rows"})}
        >
          <.icon name="hero-table-cells" class="size-4" /> {gettext("Rows")}
        </.tab>
        <.tab
          id="spool-tab-columns"
          active={@tab == "columns"}
          patch={table_path(assigns_socket(assigns), %{"tab" => "columns", "page" => 1})}
        >
          <.icon name="hero-view-columns" class="size-4" /> {gettext("Columns")}
          <span class="rounded-full bg-gray-100 px-1.5 text-[11px] text-gray-600 dark:bg-slate-800 dark:text-gray-300">
            {length(@table.columns)}
          </span>
        </.tab>
      </div>

      <%= if @tab == "rows" do %>
        <.rows_view
          table={@table}
          rows={@streams.rows}
          empty?={@empty?}
          search={@search}
          page={@page}
          pages={@pages}
          total={@total}
          can_edit={@can_edit}
          prev_path={table_path(assigns_socket(assigns), %{"page" => @page - 1})}
          next_path={table_path(assigns_socket(assigns), %{"page" => @page + 1})}
        />
      <% else %>
        <.columns_editor
          form={@columns_form}
          columns={@columns_draft}
          saved={@table.columns}
          types={@column_types}
          error={@columns_error}
          can_edit={@can_edit}
        />
      <% end %>

      <.row_editor
        :if={@editing_row}
        row={@editing_row}
        columns={@table.columns}
        error={@row_error}
      />
    </div>
    """
  end

  # `table_path/2` reads the socket's assigns, which a template has as `assigns`.
  defp assigns_socket(assigns), do: %{assigns: assigns}
end
