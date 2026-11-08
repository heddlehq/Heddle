defmodule HeddleUI.SpoolLive.Components do
  @moduledoc """
  The parts of a Spool table's page: its tabs, the grid of rows, the drawer that
  edits a row and the list of columns. See `HeddleUI.SpoolLive.Table`.
  """

  use HeddleUI, :html

  @input "w-full rounded-lg border border-gray-200 bg-gray-50 px-3 py-2 text-sm text-gray-900 placeholder-gray-400 transition-colors hover:border-gray-300 focus:border-primary focus:outline-none focus:ring-2 focus:ring-primary/20 dark:border-slate-700 dark:bg-slate-800 dark:text-gray-100 dark:placeholder-gray-500 dark:hover:border-slate-600"

  attr :id, :string, required: true
  attr :active, :boolean, default: false
  attr :patch, :string, required: true
  slot :inner_block, required: true

  def tab(assigns) do
    ~H"""
    <.link
      id={@id}
      patch={@patch}
      role="tab"
      aria-selected={to_string(@active)}
      class={[
        "-mb-px inline-flex items-center gap-2 border-b-2 px-4 py-2.5 text-sm font-medium transition-colors",
        if(@active,
          do: "border-primary text-primary",
          else:
            "border-transparent text-gray-500 hover:border-gray-300 hover:text-gray-700 dark:text-gray-400 dark:hover:border-slate-600 dark:hover:text-gray-200"
        )
      ]}
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end

  attr :table, :map, required: true
  attr :rows, :any, required: true
  attr :empty?, :boolean, required: true
  attr :search, :string, required: true
  attr :page, :integer, required: true
  attr :pages, :integer, required: true
  attr :total, :integer, required: true
  attr :can_edit, :boolean, required: true
  attr :prev_path, :string, required: true
  attr :next_path, :string, required: true

  def rows_view(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <form
          id="spool-search"
          phx-change="search"
          phx-submit="search"
          class="relative w-full sm:max-w-xs"
        >
          <.icon
            name="hero-magnifying-glass"
            class="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-gray-400"
          />
          <input
            type="search"
            name="q"
            value={@search}
            phx-debounce="300"
            placeholder={gettext("Search rows")}
            autocomplete="off"
            class={[input_class(), "pl-9"]}
          />
        </form>
        <.button
          :if={@can_edit and @table.columns != []}
          id="spool-new-row"
          variant="primary"
          phx-click="new_row"
        >
          <.icon name="hero-plus" class="size-4" /> {gettext("Add row")}
        </.button>
      </div>

      <div
        :if={@table.columns == []}
        id="spool-no-columns"
        class="rounded-xl border border-dashed border-gray-300 px-6 py-12 text-center text-sm text-gray-500 dark:border-slate-700 dark:text-gray-400"
      >
        {gettext("This table has no columns yet. Add them in the Columns tab.")}
      </div>

      <div
        :if={@table.columns != []}
        class="overflow-hidden rounded-xl border border-gray-200 bg-white shadow-sm dark:border-slate-800 dark:bg-slate-900"
      >
        <div class="overflow-x-auto">
          <table class="w-full text-left text-sm">
            <thead class="border-b border-gray-200 bg-gray-50 text-xs uppercase tracking-wide text-gray-500 dark:border-slate-800 dark:bg-slate-800/50 dark:text-gray-400">
              <tr>
                <th class="w-16 px-4 py-3 font-semibold">id</th>
                <th :for={column <- @table.columns} class="whitespace-nowrap px-4 py-3 font-semibold">
                  <span class="inline-flex items-center gap-1.5">
                    <.icon name={type_icon(column["type"])} class="size-3.5 opacity-70" />
                    {column["name"]}
                  </span>
                </th>
                <th class="whitespace-nowrap px-4 py-3 font-semibold">{gettext("Created")}</th>
              </tr>
            </thead>
            <tbody
              id="spool-rows"
              phx-update="stream"
              class="divide-y divide-gray-100 dark:divide-slate-800"
            >
              <tr id="spool-rows-empty" class="hidden only:table-row">
                <td
                  colspan={length(@table.columns) + 2}
                  class="px-4 py-12 text-center text-gray-500 dark:text-gray-400"
                >
                  {if(@search != "", do: gettext("No row matches."), else: gettext("No rows yet."))}
                </td>
              </tr>
              <tr
                :for={{id, row} <- @rows}
                id={id}
                phx-click={@can_edit && "edit_row"}
                phx-value-id={row["id"]}
                class={[
                  "transition-colors",
                  @can_edit && "cursor-pointer hover:bg-gray-50 dark:hover:bg-slate-800/60"
                ]}
              >
                <td class="px-4 py-2.5 font-mono text-xs text-gray-500 dark:text-gray-400">
                  {row["id"]}
                </td>
                <td
                  :for={column <- @table.columns}
                  class="max-w-xs px-4 py-2.5 text-gray-900 dark:text-gray-100"
                >
                  <.cell type={column["type"]} value={row[column["name"]]} />
                </td>
                <td class="whitespace-nowrap px-4 py-2.5 text-xs text-gray-500 dark:text-gray-400">
                  {short_time(row["created_at"])}
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div
          :if={@pages > 1}
          id="spool-pager"
          class="flex items-center justify-between border-t border-gray-200 px-4 py-3 text-sm dark:border-slate-800"
        >
          <span class="text-gray-500 dark:text-gray-400">
            {gettext("Page %{page} of %{pages}", page: @page, pages: @pages)}
          </span>
          <div class="flex gap-2">
            <.button :if={@page > 1} id="spool-prev" patch={@prev_path} variant="ghost">
              <.icon name="hero-chevron-left-mini" class="size-4" /> {gettext("Previous")}
            </.button>
            <.button :if={@page < @pages} id="spool-next" patch={@next_path} variant="ghost">
              {gettext("Next")} <.icon name="hero-chevron-right-mini" class="size-4" />
            </.button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :type, :string, required: true
  attr :value, :any, required: true

  defp cell(%{value: nil} = assigns) do
    ~H"""
    <span class="text-gray-300 dark:text-slate-600">—</span>
    """
  end

  defp cell(%{type: "boolean"} = assigns) do
    ~H"""
    <.icon
      name={if(@value, do: "hero-check-circle-mini", else: "hero-x-circle-mini")}
      class={[
        "size-5",
        if(@value, do: "text-emerald-600 dark:text-emerald-400", else: "text-gray-400")
      ]}
    />
    """
  end

  defp cell(%{type: "json"} = assigns) do
    ~H"""
    <code class="block truncate font-mono text-xs text-gray-600 dark:text-gray-300">
      {Jason.encode!(@value)}
    </code>
    """
  end

  defp cell(%{type: "number"} = assigns) do
    ~H"""
    <span class="font-mono tabular-nums">{@value}</span>
    """
  end

  defp cell(assigns) do
    ~H"""
    <span class="block truncate" title={to_string(@value)}>{@value}</span>
    """
  end

  attr :row, :map, required: true
  attr :columns, :list, required: true
  attr :error, :string, default: nil

  def row_editor(assigns) do
    ~H"""
    <div
      id="spool-row-editor"
      class="fixed inset-0 z-50 flex justify-end"
      phx-window-keydown="close_row"
      phx-key="Escape"
    >
      <div class="absolute inset-0 bg-slate-950/30 backdrop-blur-[1px]" phx-click="close_row" />
      <div class="relative flex h-full w-full max-w-md flex-col border-l border-gray-200 bg-white shadow-xl dark:border-slate-700 dark:bg-slate-900">
        <div class="flex items-center justify-between border-b border-gray-200 px-6 py-4 dark:border-slate-800">
          <h2 class="text-lg font-semibold text-gray-900 dark:text-white">
            {if(@row == %{}, do: gettext("New row"), else: gettext("Row %{id}", id: @row["id"]))}
          </h2>
          <button
            id="spool-row-close"
            type="button"
            phx-click="close_row"
            class="flex size-9 items-center justify-center rounded-lg text-gray-500 transition-colors hover:bg-gray-100 hover:text-gray-900 dark:text-gray-400 dark:hover:bg-slate-800 dark:hover:text-white"
          >
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>

        <.form
          for={%{}}
          as={:row}
          id="spool-row-form"
          phx-submit="save_row"
          class="flex flex-1 flex-col overflow-hidden"
        >
          <div class="flex-1 space-y-4 overflow-y-auto p-6">
            <div
              :if={@error}
              id="spool-row-error"
              class="flex gap-2 rounded-lg border border-rose-200 bg-rose-50 p-3 text-sm text-rose-700 dark:border-rose-900/50 dark:bg-rose-900/20 dark:text-rose-300"
            >
              <.icon name="hero-exclamation-circle" class="size-5 shrink-0" /> {@error}
            </div>
            <div :for={column <- @columns}>
              <label
                for={"row-#{column["id"]}"}
                class="mb-1.5 flex items-center gap-1.5 text-sm font-medium text-gray-700 dark:text-gray-300"
              >
                <.icon name={type_icon(column["type"])} class="size-3.5 text-gray-400" />
                {column["name"]}
                <span class="text-xs font-normal text-gray-400 dark:text-gray-500">
                  {type_label(column["type"])}
                </span>
              </label>
              <.row_field column={column} value={@row[column["name"]]} />
            </div>
          </div>
          <div class="flex items-center justify-between gap-2 border-t border-gray-200 px-6 py-4 dark:border-slate-800">
            <.button
              :if={@row != %{}}
              id="spool-row-delete"
              type="button"
              variant="ghost"
              phx-click="delete_row"
              phx-value-id={@row["id"]}
              data-confirm={gettext("Delete this row?")}
              class="text-rose-600 hover:bg-rose-50 dark:text-rose-400 dark:hover:bg-rose-900/20"
            >
              <.icon name="hero-trash" class="size-4" /> {gettext("Delete")}
            </.button>
            <div class="ml-auto flex gap-2">
              <.button type="button" variant="ghost" phx-click="close_row">
                {gettext("Cancel")}
              </.button>
              <.button
                id="spool-row-save"
                type="submit"
                variant="primary"
                phx-disable-with={gettext("Saving...")}
              >
                {gettext("Save")}
              </.button>
            </div>
          </div>
        </.form>
      </div>
    </div>
    """
  end

  attr :column, :map, required: true
  attr :value, :any, default: nil

  defp row_field(%{column: %{"type" => "boolean"}} = assigns) do
    ~H"""
    <select id={"row-#{@column["id"]}"} name={"row[#{@column["id"]}]"} class={input_class()}>
      <option value="" selected={is_nil(@value)}>—</option>
      <option value="true" selected={@value == true}>{gettext("Yes")}</option>
      <option value="false" selected={@value == false}>{gettext("No")}</option>
    </select>
    """
  end

  defp row_field(%{column: %{"type" => "json"}} = assigns) do
    ~H"""
    <textarea
      id={"row-#{@column["id"]}"}
      name={"row[#{@column["id"]}]"}
      rows="4"
      spellcheck="false"
      placeholder={~s({"key": "value"})}
      class={[input_class(), "font-mono"]}
    >{if(is_nil(@value), do: "", else: Jason.encode!(@value, pretty: true))}</textarea>
    """
  end

  defp row_field(%{column: %{"type" => "number"}} = assigns) do
    ~H"""
    <input
      id={"row-#{@column["id"]}"}
      type="number"
      step="any"
      name={"row[#{@column["id"]}]"}
      value={@value}
      class={[input_class(), "font-mono"]}
    />
    """
  end

  defp row_field(%{column: %{"type" => "date"}} = assigns) do
    ~H"""
    <input
      id={"row-#{@column["id"]}"}
      type="text"
      name={"row[#{@column["id"]}]"}
      value={@value}
      placeholder="2026-11-08"
      class={[input_class(), "font-mono"]}
    />
    """
  end

  defp row_field(assigns) do
    ~H"""
    <textarea
      :if={is_binary(@value) and (String.length(@value) > 60 or String.contains?(@value, "\n"))}
      id={"row-#{@column["id"]}"}
      name={"row[#{@column["id"]}]"}
      rows="4"
      class={input_class()}
    >{@value}</textarea>
    <input
      :if={not (is_binary(@value) and (String.length(@value) > 60 or String.contains?(@value, "\n")))}
      id={"row-#{@column["id"]}"}
      type="text"
      name={"row[#{@column["id"]}]"}
      value={@value}
      class={input_class()}
    />
    """
  end

  attr :form, :any, required: true
  attr :columns, :list, required: true
  attr :saved, :list, required: true
  attr :types, :list, required: true
  attr :error, :string, default: nil
  attr :can_edit, :boolean, required: true

  def columns_editor(assigns) do
    assigns = assign(assigns, :saved_types, Map.new(assigns.saved, &{&1["id"], &1["type"]}))

    ~H"""
    <.form
      for={@form}
      id="spool-columns-form"
      phx-change="columns_change"
      phx-submit="save_columns"
      class="max-w-3xl space-y-6"
    >
      <fieldset disabled={not @can_edit} class="space-y-6">
        <div class="rounded-xl border border-gray-200 bg-white p-6 shadow-sm dark:border-slate-800 dark:bg-slate-900">
          <label
            for="spool-table-name-input"
            class="mb-1.5 block text-sm font-medium text-gray-700 dark:text-gray-300"
          >
            {gettext("Table name")}
          </label>
          <input
            id="spool-table-name-input"
            type="text"
            name="table[name]"
            value={@form[:name].value}
            autocomplete="off"
            class={[input_class(), "max-w-sm"]}
          />
          <p class="mt-1.5 text-xs text-gray-500 dark:text-gray-400">
            {gettext(
              "Spool nodes find the table by this name. Renaming it breaks flows that use the old one."
            )}
          </p>
        </div>

        <div class="rounded-xl border border-gray-200 bg-white shadow-sm dark:border-slate-800 dark:bg-slate-900">
          <div class="border-b border-gray-200 px-6 py-4 dark:border-slate-800">
            <h2 class="text-base font-semibold text-gray-900 dark:text-white">
              {gettext("Columns")}
            </h2>
            <p class="mt-0.5 text-sm text-gray-500 dark:text-gray-400">
              {gettext(
                "Renaming a column keeps its values. Changing its type converts them, and removing it deletes them."
              )}
            </p>
          </div>

          <div id="spool-columns" class="divide-y divide-gray-100 dark:divide-slate-800">
            <div
              :for={{column, index} <- Enum.with_index(@columns)}
              id={"spool-column-#{index}"}
              class="flex items-center gap-3 px-6 py-3"
            >
              <input type="hidden" name={"table[columns][#{index}][id]"} value={column["id"]} />
              <input
                id={"spool-column-name-#{index}"}
                type="text"
                name={"table[columns][#{index}][name]"}
                value={column["name"]}
                placeholder={gettext("column_name")}
                autocomplete="off"
                class={[input_class(), "flex-1 font-mono"]}
              />
              <div class="relative w-36 shrink-0">
                <select
                  id={"spool-column-type-#{index}"}
                  name={"table[columns][#{index}][type]"}
                  class={[input_class(), "appearance-none pr-8"]}
                >
                  <option :for={type <- @types} value={type} selected={type == column["type"]}>
                    {type_label(type)}
                  </option>
                </select>
                <.icon
                  name="hero-chevron-down-mini"
                  class="pointer-events-none absolute right-2.5 top-1/2 size-4 -translate-y-1/2 text-gray-400"
                />
              </div>
              <span
                :if={column["id"] != "" and @saved_types[column["id"]] not in [nil, column["type"]]}
                class="shrink-0 rounded-full bg-amber-100 px-2 py-0.5 text-[11px] font-medium text-amber-800 dark:bg-amber-900/30 dark:text-amber-300"
                title={gettext("Its values will be converted when you save.")}
              >
                {gettext("converts")}
              </span>
              <span
                :if={column["id"] == ""}
                class="shrink-0 rounded-full bg-emerald-100 px-2 py-0.5 text-[11px] font-medium text-emerald-800 dark:bg-emerald-900/30 dark:text-emerald-300"
              >
                {gettext("new")}
              </span>
              <button
                :if={@can_edit}
                id={"spool-column-remove-#{index}"}
                type="button"
                phx-click="remove_column"
                phx-value-index={index}
                title={gettext("Remove column")}
                class="flex size-9 shrink-0 items-center justify-center rounded-lg text-gray-400 transition-colors hover:bg-rose-50 hover:text-rose-600 dark:hover:bg-rose-900/20 dark:hover:text-rose-400"
              >
                <.icon name="hero-trash" class="size-4" />
              </button>
            </div>
            <p
              :if={@columns == []}
              class="px-6 py-8 text-center text-sm text-gray-500 dark:text-gray-400"
            >
              {gettext("No columns yet.")}
            </p>
          </div>

          <div :if={@can_edit} class="border-t border-gray-200 px-6 py-3 dark:border-slate-800">
            <button
              id="spool-add-column"
              type="button"
              phx-click="add_column"
              class="inline-flex items-center gap-1.5 rounded-lg px-2 py-1.5 text-sm font-medium text-primary transition-colors hover:bg-primary/10"
            >
              <.icon name="hero-plus" class="size-4" /> {gettext("Add column")}
            </button>
          </div>
        </div>

        <div
          :if={@error}
          id="spool-columns-error"
          class="flex gap-2 rounded-lg border border-rose-200 bg-rose-50 p-3 text-sm text-rose-700 dark:border-rose-900/50 dark:bg-rose-900/20 dark:text-rose-300"
        >
          <.icon name="hero-exclamation-circle" class="size-5 shrink-0" /> {@error}
        </div>

        <div :if={@can_edit} class="flex gap-2">
          <.button
            id="spool-columns-save"
            type="submit"
            variant="primary"
            phx-disable-with={gettext("Saving...")}
            data-confirm={
              removes_columns?(@saved, @columns) &&
                gettext("Columns you removed take their values with them. Save?")
            }
          >
            {gettext("Save changes")}
          </.button>
          <.button id="spool-columns-reset" type="button" variant="ghost" phx-click="reset_columns">
            {gettext("Discard")}
          </.button>
        </div>
      </fieldset>
    </.form>
    """
  end

  defp removes_columns?(saved, columns) do
    kept = MapSet.new(columns, & &1["id"])
    Enum.any?(saved, &(&1["id"] not in kept))
  end

  @doc "The classes of a Spool field."
  def input_class, do: @input

  def type_icon("number"), do: "hero-hashtag"
  def type_icon("boolean"), do: "hero-check-circle"
  def type_icon("date"), do: "hero-calendar"
  def type_icon("json"), do: "hero-code-bracket"
  def type_icon(_type), do: "hero-bars-3-bottom-left"

  def type_label("text"), do: gettext("Text")
  def type_label("number"), do: gettext("Number")
  def type_label("boolean"), do: gettext("Yes / no")
  def type_label("date"), do: gettext("Date")
  def type_label("json"), do: "JSON"
  def type_label(type), do: type

  defp short_time(nil), do: ""

  defp short_time(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, at, _offset} -> Calendar.strftime(at, "%Y-%m-%d %H:%M")
      _other -> iso
    end
  end
end
