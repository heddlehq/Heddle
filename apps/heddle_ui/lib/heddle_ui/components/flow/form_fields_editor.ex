defmodule HeddleUI.Components.Flow.FormFieldsEditor do
  @moduledoc """
  Edits the fields of a Form Trigger in the node's drawer: a card per field, to name,
  type and order it. The inputs are named `fields[i][...]`, which
  `HeddleUI.FlowLive.FormManager.encode_fields/2` turns back into the JSON of the
  control. Adding, removing and moving are events of the editor.
  """

  use HeddleUI, :html

  @types [
    {"text", "Short text", "hero-minus"},
    {"textarea", "Long text", "hero-bars-3-bottom-left"},
    {"email", "Email", "hero-at-symbol"},
    {"number", "Number", "hero-hashtag"},
    {"date", "Date", "hero-calendar"},
    {"select", "Choice", "hero-list-bullet"},
    {"checkbox", "Checkbox", "hero-check-circle"}
  ]

  @input "w-full rounded-lg border border-gray-200 bg-white px-3 py-2 text-sm text-gray-900 placeholder-gray-400 transition-colors hover:border-gray-300 focus:border-primary focus:outline-none focus:ring-2 focus:ring-primary/20 dark:border-slate-700 dark:bg-slate-900 dark:text-gray-100 dark:placeholder-gray-500 dark:hover:border-slate-600"

  attr :key, :string, required: true
  attr :value, :string, default: ""
  attr :read_only, :boolean, default: false

  def form_fields(assigns) do
    assigns =
      assigns
      |> assign(:fields, Heddle.Form.parse!(assigns.value))
      |> assign(:types, @types)
      |> assign(:input, @input)

    ~H"""
    <div id="form-fields-editor" class="space-y-3">
      <div
        :for={{field, index} <- Enum.with_index(@fields)}
        id={"form-field-card-#{index}"}
        class="group rounded-xl border border-gray-200 bg-gray-50/60 p-3 transition-colors hover:border-gray-300 dark:border-slate-700 dark:bg-slate-800/40 dark:hover:border-slate-600"
      >
        <div class="flex items-center gap-2">
          <span class="flex size-7 shrink-0 items-center justify-center rounded-md bg-primary/10 text-primary">
            <.icon name={type_icon(field["type"])} class="size-4" />
          </span>
          <input
            id={"form-field-label-#{index}"}
            type="text"
            name={"#{@key}[#{index}][label]"}
            value={field["label"]}
            placeholder={gettext("Question")}
            autocomplete="off"
            class={[@input, "font-medium"]}
          />
          <div :if={not @read_only} class="flex shrink-0 items-center">
            <button
              type="button"
              phx-click="form_field_move"
              phx-value-index={index}
              phx-value-direction="up"
              disabled={index == 0}
              title={gettext("Move up")}
              class="flex size-7 items-center justify-center rounded-md text-gray-400 transition-colors hover:bg-gray-200 hover:text-gray-700 disabled:opacity-30 disabled:hover:bg-transparent dark:hover:bg-slate-700 dark:hover:text-gray-200"
            >
              <.icon name="hero-chevron-up-mini" class="size-4" />
            </button>
            <button
              type="button"
              phx-click="form_field_move"
              phx-value-index={index}
              phx-value-direction="down"
              disabled={index == length(@fields) - 1}
              title={gettext("Move down")}
              class="flex size-7 items-center justify-center rounded-md text-gray-400 transition-colors hover:bg-gray-200 hover:text-gray-700 disabled:opacity-30 disabled:hover:bg-transparent dark:hover:bg-slate-700 dark:hover:text-gray-200"
            >
              <.icon name="hero-chevron-down-mini" class="size-4" />
            </button>
            <button
              id={"form-field-remove-#{index}"}
              type="button"
              phx-click="form_field_remove"
              phx-value-index={index}
              title={gettext("Remove field")}
              class="flex size-7 items-center justify-center rounded-md text-gray-400 transition-colors hover:bg-rose-50 hover:text-rose-600 dark:hover:bg-rose-900/20 dark:hover:text-rose-400"
            >
              <.icon name="hero-trash-mini" class="size-4" />
            </button>
          </div>
        </div>

        <div class="mt-2 grid grid-cols-2 gap-2">
          <div class="relative">
            <select
              id={"form-field-type-#{index}"}
              name={"#{@key}[#{index}][type]"}
              aria-label={gettext("Type")}
              class={[@input, "appearance-none pr-8"]}
            >
              <option
                :for={{value, label, _icon} <- @types}
                value={value}
                selected={value == field["type"]}
              >
                {type_label(value, label)}
              </option>
            </select>
            <.icon
              name="hero-chevron-down-mini"
              class="pointer-events-none absolute right-2.5 top-1/2 size-4 -translate-y-1/2 text-gray-400"
            />
          </div>
          <div class="relative">
            <span class="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 font-mono text-xs text-gray-400">
              form.
            </span>
            <input
              id={"form-field-key-#{index}"}
              type="text"
              name={"#{@key}[#{index}][key]"}
              value={field["key"]}
              aria-label={gettext("Key")}
              title={gettext("Where the answer is in the run")}
              autocomplete="off"
              spellcheck="false"
              class={[@input, "pl-12 font-mono text-xs"]}
            />
          </div>
        </div>

        <input
          :if={field["type"] != "checkbox"}
          id={"form-field-placeholder-#{index}"}
          type="text"
          name={"#{@key}[#{index}][placeholder]"}
          value={field["placeholder"]}
          placeholder={gettext("Hint inside the field (optional)")}
          autocomplete="off"
          class={[@input, "mt-2"]}
        />

        <textarea
          :if={field["type"] == "select"}
          id={"form-field-options-#{index}"}
          name={"#{@key}[#{index}][options]"}
          rows="3"
          placeholder={gettext("One option per line")}
          class={[@input, "mt-2"]}
        >{Enum.join(field["options"], "\n")}</textarea>

        <label class="mt-2 inline-flex cursor-pointer items-center gap-2 text-xs text-gray-600 dark:text-gray-300">
          <input type="hidden" name={"#{@key}[#{index}][required]"} value="false" />
          <input
            id={"form-field-required-#{index}"}
            type="checkbox"
            name={"#{@key}[#{index}][required]"}
            value="true"
            checked={field["required"]}
            class="size-4 rounded border-gray-300 accent-primary focus:ring-primary dark:border-slate-600"
          />
          {gettext("Required")}
        </label>
      </div>

      <p
        :if={@fields == []}
        class="rounded-xl border border-dashed border-gray-300 px-4 py-6 text-center text-sm text-gray-500 dark:border-slate-700 dark:text-gray-400"
      >
        {gettext("No fields yet.")}
      </p>

      <button
        :if={not @read_only}
        id="form-field-add"
        type="button"
        phx-click="form_field_add"
        class="flex w-full items-center justify-center gap-1.5 rounded-xl border border-dashed border-gray-300 px-4 py-2.5 text-sm font-medium text-gray-600 transition-colors hover:border-primary hover:bg-primary/5 hover:text-primary dark:border-slate-600 dark:text-gray-300"
      >
        <.icon name="hero-plus-mini" class="size-4" /> {gettext("Add field")}
      </button>
    </div>
    """
  end

  defp type_icon(type) do
    Enum.find_value(@types, "hero-minus", fn {value, _label, icon} -> value == type && icon end)
  end

  defp type_label("text", _label), do: gettext("Short text")
  defp type_label("textarea", _label), do: gettext("Long text")
  defp type_label("email", _label), do: gettext("Email")
  defp type_label("number", _label), do: gettext("Number")
  defp type_label("date", _label), do: gettext("Date")
  defp type_label("select", _label), do: gettext("Choice")
  defp type_label("checkbox", _label), do: gettext("Checkbox")
  defp type_label(_value, label), do: label
end
