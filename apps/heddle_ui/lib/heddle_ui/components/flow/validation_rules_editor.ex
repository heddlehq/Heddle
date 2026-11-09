defmodule HeddleUI.Components.Flow.ValidationRulesEditor do
  @moduledoc """
  Edits the rules of a Validate node in the drawer: a card per field, with its type,
  whether it is required, the limits its type takes and its error message in each
  language. The inputs are named `<key>[i][...]`, which
  `HeddleUI.FlowLive.ValidateManager.encode/2` turns back into the schema's JSON.

  A schema the cards can't show, like nested objects, is edited as JSON.
  """

  use HeddleUI, :html

  alias HeddleUI.FlowLive.ValidateRules

  @input "w-full rounded-lg border border-gray-200 bg-white px-3 py-2 text-sm text-gray-900 placeholder-gray-400 transition-colors hover:border-gray-300 focus:border-primary focus:outline-none focus:ring-2 focus:ring-primary/20 dark:border-slate-700 dark:bg-slate-900 dark:text-gray-100 dark:placeholder-gray-500 dark:hover:border-slate-600"
  @small_label "mb-1 block text-xs font-medium text-gray-500 dark:text-gray-400"

  attr :key, :string, required: true
  attr :value, :string, default: ""
  attr :read_only, :boolean, default: false
  attr :json, :boolean, default: false, doc: "whether the person asked for the JSON"
  attr :form, :boolean, default: false, doc: "whether the flow has a form to start from"

  def rules(assigns) do
    parsed = ValidateRules.from_schema(assigns.value)

    assigns =
      assigns
      |> assign(:parsed, parsed)
      |> assign(:show_json, assigns.json or parsed == :complex)
      |> assign(:input, @input)
      |> assign(:small_label, @small_label)

    ~H"""
    <div id="validate-rules-editor" class="space-y-3">
      <%= if @show_json do %>
        <textarea
          id={"node-field-#{@key}"}
          name={@key}
          rows="12"
          spellcheck="false"
          class="w-full rounded-lg border border-gray-200 bg-gray-50 px-4 py-3 font-mono text-sm text-gray-900 transition-all duration-150 hover:border-gray-300 focus:border-primary focus:outline-none focus:ring-2 focus:ring-primary/20 dark:border-slate-700 dark:bg-slate-800 dark:text-gray-100 dark:hover:border-slate-600"
        >{@value}</textarea>
        <p
          :if={@parsed == :complex}
          id="validate-json-only"
          class="text-xs text-gray-500 dark:text-gray-400"
        >
          {gettext(
            "This schema has what only JSON says, like fields inside fields, so it is edited as JSON."
          )}
        </p>
        <button
          :if={@parsed != :complex}
          id="validate-json-toggle"
          type="button"
          phx-click="validate_toggle_json"
          class="text-xs font-medium text-primary hover:underline"
        >
          {gettext("Back to the fields")}
        </button>
      <% else %>
        <% {:ok, rules} = @parsed %>
        <button
          :if={@form and not @read_only}
          id="validate-use-form"
          type="button"
          phx-click="validate_use_form"
          data-confirm={
            rules != [] &&
              gettext("The rules below are replaced by the fields of the form. Go on?")
          }
          class="flex w-full items-center justify-center gap-1.5 rounded-xl border border-primary/30 bg-primary/5 px-4 py-2.5 text-sm font-medium text-primary transition-colors hover:bg-primary/10"
        >
          <.icon name="hero-document-text-mini" class="size-4" />
          {gettext("Use the fields of the form")}
        </button>

        <.rule
          :for={{rule, index} <- Enum.with_index(rules)}
          rule={rule}
          index={index}
          key={@key}
          read_only={@read_only}
          input={@input}
          small_label={@small_label}
        />

        <p
          :if={rules == []}
          class="rounded-xl border border-dashed border-gray-300 px-4 py-6 text-center text-sm text-gray-500 dark:border-slate-700 dark:text-gray-400"
        >
          {gettext("No fields yet: anything passes.")}
        </p>

        <button
          :if={not @read_only}
          id="validate-rule-add"
          type="button"
          phx-click="validate_rule_add"
          class="flex w-full items-center justify-center gap-1.5 rounded-xl border border-dashed border-gray-300 px-4 py-2.5 text-sm font-medium text-gray-600 transition-colors hover:border-primary hover:bg-primary/5 hover:text-primary dark:border-slate-600 dark:text-gray-300"
        >
          <.icon name="hero-plus-mini" class="size-4" /> {gettext("Add field")}
        </button>

        <button
          id="validate-json-toggle"
          type="button"
          phx-click="validate_toggle_json"
          class="text-xs font-medium text-gray-500 hover:text-primary hover:underline dark:text-gray-400"
        >
          {gettext("Edit as JSON")}
        </button>
      <% end %>
    </div>
    """
  end

  attr :rule, :map, required: true
  attr :index, :integer, required: true
  attr :key, :string, required: true
  attr :read_only, :boolean, required: true
  attr :input, :string, required: true
  attr :small_label, :string, required: true

  defp rule(assigns) do
    assigns = assign(assigns, :name, "#{assigns.key}[#{assigns.index}]")

    ~H"""
    <div
      id={"validate-rule-#{@index}"}
      class="rounded-xl border border-gray-200 bg-gray-50/60 p-3 transition-colors hover:border-gray-300 dark:border-slate-700 dark:bg-slate-800/40 dark:hover:border-slate-600"
    >
      <div class="flex items-center gap-2">
        <div class="relative min-w-0 flex-1">
          <span class="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 font-mono text-xs text-gray-400">
            {gettext("field")}
          </span>
          <input
            id={"validate-rule-key-#{@index}"}
            type="text"
            name={"#{@name}[key]"}
            value={@rule["key"]}
            aria-label={gettext("Field")}
            placeholder="email"
            autocomplete="off"
            spellcheck="false"
            class={[
              @input,
              "pl-14 font-mono text-xs",
              @rule["key"] == "" && "border-rose-400 dark:border-rose-500/70"
            ]}
          />
        </div>
        <button
          :if={not @read_only}
          id={"validate-rule-remove-#{@index}"}
          type="button"
          phx-click="validate_rule_remove"
          phx-value-index={@index}
          title={gettext("Remove field")}
          class="flex w-9 shrink-0 self-stretch items-center justify-center rounded-md text-gray-400 transition-colors hover:bg-rose-50 hover:text-rose-600 dark:hover:bg-rose-900/20 dark:hover:text-rose-400"
        >
          <.icon name="hero-trash-mini" class="size-4" />
        </button>
      </div>

      <div class="mt-2 relative">
        <select
          id={"validate-rule-type-#{@index}"}
          name={"#{@name}[type]"}
          aria-label={gettext("Type")}
          class={[@input, "appearance-none pr-8"]}
        >
          <option
            :for={type <- ValidateRules.types()}
            value={type}
            selected={type == @rule["type"]}
          >
            {type_label(type)}
          </option>
        </select>
        <.icon
          name="hero-chevron-down-mini"
          class="pointer-events-none absolute right-2.5 top-1/2 size-4 -translate-y-1/2 text-gray-400"
        />
      </div>

      <div
        :if={@rule["type"] in ~w(string email url number integer date)}
        class="mt-2 grid grid-cols-2 gap-2"
      >
        <div>
          <label for={"validate-rule-min-#{@index}"} class={@small_label}>
            {bound_label(@rule["type"], :min)}
          </label>
          <input
            id={"validate-rule-min-#{@index}"}
            type={bound_type(@rule["type"])}
            min={if(@rule["type"] in ~w(string email url), do: "0")}
            step={if(@rule["type"] == "number", do: "any")}
            name={"#{@name}[min]"}
            value={@rule["min"]}
            class={@input}
          />
        </div>
        <div>
          <label for={"validate-rule-max-#{@index}"} class={@small_label}>
            {bound_label(@rule["type"], :max)}
          </label>
          <input
            id={"validate-rule-max-#{@index}"}
            type={bound_type(@rule["type"])}
            min={if(@rule["type"] in ~w(string email url), do: "0")}
            step={if(@rule["type"] == "number", do: "any")}
            name={"#{@name}[max]"}
            value={@rule["max"]}
            class={@input}
          />
        </div>
      </div>

      <div :if={@rule["type"] == "string"} class="mt-2">
        <label for={"validate-rule-pattern-#{@index}"} class={@small_label}>
          {gettext("Format (regular expression, optional)")}
        </label>
        <input
          id={"validate-rule-pattern-#{@index}"}
          type="text"
          name={"#{@name}[pattern]"}
          value={@rule["pattern"]}
          placeholder="^\d{11}$"
          autocomplete="off"
          spellcheck="false"
          class={[@input, "font-mono text-xs"]}
        />
        <p
          :if={not ValidateRules.valid_pattern?(@rule["pattern"])}
          id={"validate-rule-pattern-error-#{@index}"}
          class="mt-1 flex items-center gap-1 text-xs text-rose-600 dark:text-rose-400"
        >
          <.icon name="hero-exclamation-circle-mini" class="size-4" />
          {gettext("This isn't a regular expression that can be read.")}
        </p>
      </div>

      <div :if={@rule["type"] == "enum"} class="mt-2">
        <label for={"validate-rule-options-#{@index}"} class={@small_label}>
          {gettext("Allowed values, one per line")}
        </label>
        <textarea
          id={"validate-rule-options-#{@index}"}
          name={"#{@name}[options]"}
          rows="3"
          class={@input}
        >{@rule["options"]}</textarea>
      </div>

      <label class="mt-2 inline-flex cursor-pointer items-center gap-2 text-xs text-gray-600 dark:text-gray-300">
        <input type="hidden" name={"#{@name}[required]"} value="false" />
        <input
          id={"validate-rule-required-#{@index}"}
          type="checkbox"
          name={"#{@name}[required]"}
          value="true"
          checked={@rule["required"]}
          class="size-4 rounded border-gray-300 accent-primary focus:ring-primary dark:border-slate-600"
        />
        {gettext("Required")}
      </label>

      <div class="mt-3 border-t border-gray-200 pt-3 dark:border-slate-700">
        <p class={@small_label}>{gettext("Error message")}</p>
        <div class="space-y-2">
          <div :for={language <- ValidateRules.languages()} class="relative">
            <span class="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 rounded bg-gray-100 px-1.5 py-0.5 font-mono text-[10px] font-semibold uppercase text-gray-500 dark:bg-slate-800 dark:text-gray-400">
              {language_tag(language)}
            </span>
            <input
              id={"validate-rule-message-#{@index}-#{language}"}
              type="text"
              name={"#{@name}[message][#{language}]"}
              value={@rule["message"][language]}
              placeholder={gettext("Usual message")}
              aria-label={gettext("Error message in %{language}", language: language_name(language))}
              autocomplete="off"
              class={[@input, "pl-12"]}
            />
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp type_label("string"), do: gettext("Text")
  defp type_label("email"), do: gettext("Email")
  defp type_label("url"), do: gettext("Link")
  defp type_label("number"), do: gettext("Number")
  defp type_label("integer"), do: gettext("Whole number")
  defp type_label("date"), do: gettext("Date")
  defp type_label("boolean"), do: gettext("Yes or no")
  defp type_label("enum"), do: gettext("One of a list")

  defp bound_label(type, :min) when type in ~w(string email url), do: gettext("Min. characters")
  defp bound_label(type, :max) when type in ~w(string email url), do: gettext("Max. characters")
  defp bound_label("date", :min), do: gettext("From")
  defp bound_label("date", :max), do: gettext("Until")
  defp bound_label(_type, :min), do: gettext("Minimum")
  defp bound_label(_type, :max), do: gettext("Maximum")

  defp bound_type("date"), do: "date"
  defp bound_type(_type), do: "number"

  defp language_tag("pt_BR"), do: "PT"
  defp language_tag(language), do: String.upcase(language)

  defp language_name("en"), do: "English"
  defp language_name("pt_BR"), do: "Português"
  defp language_name(language), do: language
end
