defmodule HeddleUI.Components.Modals.NodeConfigModal do
  use HeddleUI, :html

  alias HeddleUI.AIChoices
  alias HeddleUI.FlowLive.NodeCode
  alias HeddleUI.FlowLive.NodeSettings

  attr :config_modal_open, :boolean, required: true
  attr :editing_node_data, :map, default: nil
  attr :credentials, :list, default: []
  attr :read_only, :boolean, default: false

  def node_config_modal(assigns) do
    ~H"""
    <div class={[
      "fixed top-0 right-0 h-full w-[400px] z-[100] bg-white dark:bg-slate-900 border-l border-gray-200 dark:border-slate-700 shadow-xl dark:shadow-none flex flex-col transition-transform duration-300 ease-[cubic-bezier(0.16,1,0.3,1)]",
      if(@config_modal_open, do: "translate-x-0", else: "translate-x-full")
    ]}>
      <%= if @editing_node_data do %>
        <div class="sticky top-0 z-10 flex items-center justify-between px-6 py-4 border-b border-gray-200 dark:border-slate-800 bg-white dark:bg-slate-900">
          <div class="flex items-center gap-3 min-w-0">
            <span class="shrink-0 p-2 rounded-lg bg-primary/10 text-primary">
              <.icon name={node_icon(@editing_node_data["type"])} class="w-5 h-5" />
            </span>
            <div class="min-w-0">
              <p class="text-lg font-semibold text-gray-900 dark:text-white leading-tight">
                {@editing_node_data["type"] || @editing_node_data["label"]}
              </p>
              <%= if @editing_node_data["type"] && @editing_node_data["label"] != @editing_node_data["type"] do %>
                <p class="text-sm text-gray-500 dark:text-gray-400 truncate">
                  {@editing_node_data["label"]}
                </p>
              <% end %>
            </div>
          </div>
          <button
            phx-click="close_config_modal"
            class="shrink-0 flex items-center justify-center w-9 h-9 hover:bg-gray-100 dark:hover:bg-slate-800 rounded-lg transition-colors text-gray-500 dark:text-gray-400 hover:text-gray-900 dark:hover:text-white"
          >
            <.icon name="hero-x-mark" class="w-5 h-5" />
          </button>
        </div>

        <form
          id="node-config-form"
          phx-change="node_config_changed"
          phx-submit="save_node_config"
          class="flex-1 flex flex-col overflow-hidden"
        >
          <fieldset disabled={@read_only} class="contents">
            <div class="flex-1 p-6 overflow-y-auto space-y-5">
              <div>
                <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1.5">
                  Node Name
                </label>
                <input
                  type="text"
                  name="node_label"
                  value={@editing_node_data["label"]}
                  class="w-full px-4 py-3 rounded-lg text-sm text-gray-900 dark:text-gray-100 bg-gray-50 dark:bg-slate-800 border border-gray-200 dark:border-slate-700 placeholder-gray-400 dark:placeholder-gray-500 focus:outline-none focus:border-primary focus:ring-2 focus:ring-primary/20 hover:border-gray-300 dark:hover:border-slate-600 transition-all duration-150"
                />
              </div>

              <%= if @editing_node_data["controls"] do %>
                <%= for {key, control} <- ordered_controls(@editing_node_data) do %>
                  <%= if control["type"] == "hidden" do %>
                    <input type="hidden" name={key} value={control["value"]} />
                  <% else %>
                    <div>
                      <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1.5 first-letter:uppercase">
                        {control["label"] || String.replace(key, "_", " ")}
                      </label>
                      <%= case control["type"] do %>
                        <% "select" -> %>
                          <div class="relative">
                            <select
                              name={key}
                              class="w-full px-4 py-3 rounded-lg text-sm text-gray-900 dark:text-gray-100 bg-gray-50 dark:bg-slate-800 border border-gray-200 dark:border-slate-700 focus:outline-none focus:border-primary focus:ring-2 focus:ring-primary/20 hover:border-gray-300 dark:hover:border-slate-600 transition-all duration-150 appearance-none pr-10"
                            >
                              <%= for option <- control["options"] || [] do %>
                                <%= if is_map(option) do %>
                                  <option
                                    value={option["value"]}
                                    selected={option["value"] == control["value"]}
                                  >
                                    {option["label"]}
                                  </option>
                                <% else %>
                                  <option value={option} selected={option == control["value"]}>
                                    {option}
                                  </option>
                                <% end %>
                              <% end %>
                            </select>
                            <span class="pointer-events-none absolute right-3 top-1/2 -translate-y-1/2 text-gray-400 dark:text-gray-400">
                              <.icon name="hero-chevron-down" class="w-4 h-4" />
                            </span>
                          </div>
                        <% "variable-select" -> %>
                          <div class="relative">
                            <select
                              name={key}
                              class="w-full px-4 py-3 rounded-lg text-sm text-gray-900 dark:text-gray-100 bg-gray-50 dark:bg-slate-800 border border-gray-200 dark:border-slate-700 focus:outline-none focus:border-primary focus:ring-2 focus:ring-primary/20 hover:border-gray-300 dark:hover:border-slate-600 transition-all duration-150 appearance-none pr-10"
                            >
                              <option value="">Select a variable...</option>
                              <%= for var <- @editing_node_data["variables"] || [] do %>
                                <option value={var} selected={var == control["value"]}>{var}</option>
                              <% end %>
                            </select>
                            <span class="pointer-events-none absolute right-3 top-1/2 -translate-y-1/2 text-gray-400 dark:text-gray-400">
                              <.icon name="hero-chevron-down" class="w-4 h-4" />
                            </span>
                          </div>
                        <% "credential" -> %>
                          <.credential_field
                            key={key}
                            value={control["value"]}
                            kind={control["credential_kind"]}
                            credentials={@credentials}
                            blank={credential_blank(@editing_node_data, control)}
                          />
                        <% "model" -> %>
                          <.model_field
                            key={key}
                            fields={
                              @editing_node_data
                              |> control_values()
                              |> with_workspace(@credentials)
                            }
                            capability={capability(@editing_node_data)}
                          />
                        <% type when type in ["code-icon", "code-button"] -> %>
                          <.code_field
                            key={key}
                            value={control["value"]}
                            code={
                              NodeCode.current(NodeCode.from_controls(@editing_node_data["controls"]))
                            }
                          />
                        <% "textarea" -> %>
                          <textarea
                            id={"node-field-#{key}"}
                            name={key}
                            rows="6"
                            spellcheck="false"
                            class="w-full px-4 py-3 rounded-lg font-mono text-sm text-gray-900 dark:text-gray-100 bg-gray-50 dark:bg-slate-800 border border-gray-200 dark:border-slate-700 placeholder-gray-400 dark:placeholder-gray-500 focus:outline-none focus:border-primary focus:ring-2 focus:ring-primary/20 hover:border-gray-300 dark:hover:border-slate-600 transition-all duration-150"
                          >{control["value"]}</textarea>
                        <% _ -> %>
                          <%= if String.length(to_string(control["value"])) > 50 do %>
                            <textarea
                              name={key}
                              rows="4"
                              class="w-full px-4 py-3 rounded-lg text-sm text-gray-900 dark:text-gray-100 bg-gray-50 dark:bg-slate-800 border border-gray-200 dark:border-slate-700 placeholder-gray-400 dark:placeholder-gray-500 focus:outline-none focus:border-primary focus:ring-2 focus:ring-primary/20 hover:border-gray-300 dark:hover:border-slate-600 transition-all duration-150"
                            >{control["value"]}</textarea>
                          <% else %>
                            <input
                              type="text"
                              name={key}
                              value={control["value"]}
                              class="w-full px-4 py-3 rounded-lg text-sm text-gray-900 dark:text-gray-100 bg-gray-50 dark:bg-slate-800 border border-gray-200 dark:border-slate-700 placeholder-gray-400 dark:placeholder-gray-500 focus:outline-none focus:border-primary focus:ring-2 focus:ring-primary/20 hover:border-gray-300 dark:hover:border-slate-600 transition-all duration-150"
                            />
                          <% end %>
                      <% end %>
                    </div>
                  <% end %>
                <% end %>
              <% else %>
                <p class="text-sm text-gray-500 dark:text-gray-400 italic">
                  No configuration options available for this node.
                </p>
              <% end %>

              <.node_settings
                settings={@editing_node_data["settings"] || %{}}
                type={@editing_node_data["type"]}
                unpin={@editing_node_data["unpin"] == true}
              />
            </div>
          </fieldset>
          <div class="sticky bottom-0 z-10 flex justify-end gap-3 px-6 py-4 border-t border-gray-200 dark:border-slate-800 bg-white dark:bg-slate-900">
            <button
              type="button"
              phx-click="close_config_modal"
              class="text-sm font-medium text-gray-600 dark:text-gray-400 hover:text-gray-900 dark:hover:text-white px-4 py-2.5 rounded-lg hover:bg-gray-100 dark:hover:bg-slate-800 transition-colors"
            >
              {gettext("Cancel")}
            </button>
            <button
              :if={not @read_only}
              type="submit"
              class="text-sm font-medium text-primary-content bg-primary hover:bg-primary/90 px-5 py-2.5 rounded-lg transition-colors shadow-sm active:scale-[0.98]"
            >
              {gettext("Save")}
            </button>
          </div>
        </form>
      <% end %>
    </div>
    """
  end

  attr :settings, :map, required: true
  attr :type, :string, default: nil
  attr :unpin, :boolean, default: false

  # How the node behaves when it runs, see `Heddle.Graph.Settings`.
  defp node_settings(assigns) do
    assigns =
      assigns
      |> assign(:values, NodeSettings.values(assigns.settings))
      |> assign(:own_error_output, NodeSettings.own_error_output?(assigns.type))

    ~H"""
    <section id="node-settings" class="space-y-4 border-t border-gray-200 pt-5 dark:border-slate-800">
      <div>
        <h4 class="text-sm font-semibold text-gray-900 dark:text-white">
          {gettext("When it fails")}
        </h4>
        <p class="mt-0.5 text-xs text-gray-500 dark:text-gray-400">
          {gettext("Try again, and what the run does once no try is left.")}
        </p>
      </div>

      <div class="grid grid-cols-2 gap-3">
        <label class="block">
          <span class="mb-1.5 block text-xs font-medium text-gray-700 dark:text-gray-300">
            {gettext("Tries again")}
          </span>
          <input
            id="node-settings-retries"
            type="number"
            name="settings[retries]"
            min="0"
            max="10"
            value={@values["retries"]}
            class="w-full rounded-lg border border-gray-200 bg-gray-50 px-3 py-2 text-sm text-gray-900 transition focus:border-primary focus:outline-none focus:ring-2 focus:ring-primary/20 dark:border-slate-700 dark:bg-slate-800 dark:text-gray-100"
          />
        </label>
        <label class={["block transition-opacity", @values["retries"] == 0 && "opacity-50"]}>
          <span class="mb-1.5 block text-xs font-medium text-gray-700 dark:text-gray-300">
            {gettext("Seconds between tries")}
          </span>
          <input
            id="node-settings-delay"
            type="number"
            name="settings[retry_delay]"
            min="0"
            max="300"
            step="0.5"
            value={@values["retry_delay"]}
            disabled={@values["retries"] == 0}
            class="w-full rounded-lg border border-gray-200 bg-gray-50 px-3 py-2 text-sm text-gray-900 transition focus:border-primary focus:outline-none focus:ring-2 focus:ring-primary/20 disabled:cursor-not-allowed dark:border-slate-700 dark:bg-slate-800 dark:text-gray-100"
          />
        </label>
      </div>

      <label :if={@values["retries"] > 0} class="flex cursor-pointer items-center gap-2.5">
        <input type="hidden" name="settings[retry_backoff]" value="fixed" />
        <input
          id="node-settings-backoff"
          type="checkbox"
          name="settings[retry_backoff]"
          value="exponential"
          checked={@values["retry_backoff"] == "exponential"}
          class="size-4 rounded border-gray-300 accent-primary text-primary focus:ring-primary/30 dark:border-slate-600 dark:bg-slate-800"
        />
        <span class="text-sm text-gray-700 dark:text-gray-300">
          {gettext("Wait twice as long after each try")}
        </span>
      </label>

      <fieldset class="space-y-2">
        <legend class="mb-1.5 text-xs font-medium text-gray-700 dark:text-gray-300">
          {gettext("Then")}
        </legend>
        <.on_error_option
          value="stop"
          current={@values["on_error"]}
          title={gettext("Stop the run")}
          description={
            if(@own_error_output,
              do: gettext("Unless something is connected to its error output."),
              else: gettext("The run fails at this step.")
            )
          }
        />
        <.on_error_option
          value="continue"
          current={@values["on_error"]}
          title={gettext("Continue")}
          description={gettext("The run goes on, with the error as the result.")}
        />
        <.on_error_option
          :if={!@own_error_output}
          value="output"
          current={@values["on_error"]}
          title={gettext("Use an error output")}
          description={gettext("The node gets an error output, to handle the failure there.")}
        />
      </fieldset>

      <div
        :if={@values["pin"]}
        id="node-settings-pin"
        class={[
          "space-y-2 rounded-lg border border-primary/30 bg-primary/5 p-3 transition-opacity",
          @unpin && "opacity-50"
        ]}
      >
        <div class="flex items-center justify-between gap-2">
          <p class="flex items-center gap-1.5 text-sm font-semibold text-primary">
            <.icon name="hero-bookmark-solid" class="size-4" /> {gettext("Pinned data")}
          </p>
          <label class="flex cursor-pointer items-center gap-1.5 text-xs font-medium text-gray-600 dark:text-gray-300">
            <input
              id="node-settings-unpin"
              type="checkbox"
              name="settings[unpin]"
              value="true"
              checked={@unpin}
              class="size-3.5 rounded border-gray-300 accent-primary text-primary focus:ring-primary/30 dark:border-slate-600 dark:bg-slate-800"
            />
            {gettext("Unpin")}
          </label>
        </div>
        <p class="text-xs text-gray-500 dark:text-gray-400">
          {gettext(
            "Runs from the editor take this instead of running the node, and leave through %{output}. Other runs ignore it.",
            output: @values["pin"]["output"]
          )}
        </p>
        <input type="hidden" name="settings[pin_output]" value={@values["pin"]["output"]} />
        <textarea
          id="node-settings-pin-data"
          name="settings[pin_data]"
          rows="6"
          spellcheck="false"
          class="w-full rounded-lg border border-gray-200 bg-white px-3 py-2 font-mono text-xs text-gray-900 focus:border-primary focus:outline-none focus:ring-2 focus:ring-primary/20 dark:border-slate-700 dark:bg-slate-900 dark:text-gray-100"
        >{@values["pin_data"]}</textarea>
      </div>
    </section>
    """
  end

  attr :value, :string, required: true
  attr :current, :string, required: true
  attr :title, :string, required: true
  attr :description, :string, required: true

  defp on_error_option(assigns) do
    ~H"""
    <label class={[
      "flex cursor-pointer items-start gap-3 rounded-lg border px-3 py-2.5 transition",
      if(@value == @current,
        do: "border-primary bg-primary/5",
        else:
          "border-gray-200 hover:border-gray-300 dark:border-slate-700 dark:hover:border-slate-600"
      )
    ]}>
      <input
        id={"node-settings-on-error-#{@value}"}
        type="radio"
        name="settings[on_error]"
        value={@value}
        checked={@value == @current}
        class="mt-0.5 size-4 border-gray-300 accent-primary text-primary focus:ring-primary/30 dark:border-slate-600 dark:bg-slate-800"
      />
      <span>
        <span class="block text-sm font-medium text-gray-900 dark:text-white">{@title}</span>
        <span class="block text-xs text-gray-500 dark:text-gray-400">{@description}</span>
      </span>
    </label>
    """
  end

  # The credential picked is looked up where the run will look: the workspace's own
  # first, then a shared one.
  defp with_workspace(fields, credentials) do
    case Enum.find(credentials, &(&1.name == fields["credential"] and &1.workspace_id)) ||
           Enum.find(credentials, &(&1.name == fields["credential"])) do
      nil -> fields
      credential -> Map.put(fields, "workspace_id", credential.workspace_id)
    end
  end

  attr :key, :string, required: true
  attr :fields, :map, required: true
  attr :capability, :atom, required: true

  defp model_field(assigns) do
    assigns = assign(assigns, :choice, AIChoices.model_choice(assigns.fields, assigns.capability))

    ~H"""
    <div class="relative">
      <select
        id={"node-model-#{@key}"}
        name={@key}
        disabled={@choice.options == []}
        class="w-full px-4 py-3 rounded-lg text-sm text-gray-900 dark:text-gray-100 bg-gray-50 dark:bg-slate-800 border border-gray-200 dark:border-slate-700 focus:outline-none focus:border-primary focus:ring-2 focus:ring-primary/20 hover:border-gray-300 dark:hover:border-slate-600 transition-all duration-150 appearance-none pr-10 disabled:opacity-60 disabled:cursor-not-allowed"
      >
        <option value="">
          {if(@choice.default,
            do: gettext("Default: %{model}", model: @choice.default),
            else: gettext("Nothing available")
          )}
        </option>
        <option
          :for={{label, id} <- @choice.options}
          value={id}
          selected={id == @choice.value}
        >
          {label}
        </option>
      </select>
      <span class="pointer-events-none absolute right-3 top-1/2 -translate-y-1/2 text-gray-400 dark:text-gray-400">
        <.icon name="hero-chevron-down" class="w-4 h-4" />
      </span>
    </div>
    <p :if={@choice.problem} id={"node-model-#{@key}-problem"} class="mt-1.5 text-xs text-error">
      {@choice.problem}
    </p>
    <.link navigate={~p"/ai"} class="mt-1.5 inline-block text-xs text-primary hover:underline">
      {gettext("AI settings")}
    </.link>
    """
  end

  attr :key, :string, required: true
  attr :value, :any, required: true
  attr :kind, :string, default: nil
  attr :credentials, :list, required: true
  attr :blank, :string, required: true

  defp credential_field(assigns) do
    assigns =
      assign(assigns, :options, Enum.filter(assigns.credentials, &(&1.kind == assigns.kind)))

    ~H"""
    <div class="relative">
      <select
        id={"node-credential-#{@key}"}
        name={@key}
        class="w-full px-4 py-3 rounded-lg text-sm text-gray-900 dark:text-gray-100 bg-gray-50 dark:bg-slate-800 border border-gray-200 dark:border-slate-700 focus:outline-none focus:border-primary focus:ring-2 focus:ring-primary/20 hover:border-gray-300 dark:hover:border-slate-600 transition-all duration-150 appearance-none pr-10"
      >
        <option value="">{@blank}</option>
        <option
          :for={credential <- @options}
          value={credential.name}
          selected={credential.name == @value}
        >
          {credential.name}
        </option>
      </select>
      <span class="pointer-events-none absolute right-3 top-1/2 -translate-y-1/2 text-gray-400 dark:text-gray-400">
        <.icon name="hero-chevron-down" class="w-4 h-4" />
      </span>
    </div>
    <.link
      navigate={~p"/credentials"}
      class="mt-1.5 inline-block text-xs text-primary hover:underline"
    >
      {gettext("Manage credentials")}
    </.link>
    """
  end

  attr :key, :string, required: true
  attr :value, :any, required: true
  attr :code, :string, required: true

  defp code_field(assigns) do
    ~H"""
    <div class="relative group rounded-lg overflow-hidden border border-gray-200 dark:border-slate-700">
      <pre
        id={"node-code-preview-#{@key}"}
        class="p-3 text-xs font-mono text-gray-300 bg-slate-800 dark:bg-slate-950 overflow-hidden leading-relaxed min-h-[72px]"
      ><code :if={@code != ""}>{String.slice(@code, 0, 150)}</code><span :if={@code == ""} class="text-gray-400">{gettext("No code yet")}</span></pre>
      <.button
        id={"edit-code-#{@key}"}
        type="button"
        variant="primary"
        phx-click="open_code_editor_from_config"
        phx-value-field-name={@key}
        class="absolute bottom-2 right-2 px-3 py-1.5 text-xs h-auto"
      >
        <.icon name="hero-code-bracket" class="w-3.5 h-3.5 mr-1" /> {gettext("Edit Code")}
      </.button>
      <input type="hidden" name={@key} value={@value} />
    </div>
    """
  end

  defp control_values(%{"controls" => controls}) do
    Map.new(controls, fn {key, control} -> {key, control["value"]} end)
  end

  defp capability(data) do
    Enum.find_value(definition_fields(data), &Map.get(&1, :capability))
  end

  defp credential_blank(data, %{"credential_kind" => "ai"}) do
    AIChoices.credential_default(capability(data))
  end

  defp credential_blank(_data, _control), do: gettext("Pick a credential")

  defp definition_fields(data) do
    case HeddleNodes.Nodes.get_node(data["type"]) do
      nil -> []
      node -> Map.get(node, :ui_fields, [])
    end
  end

  # Controls arrive as a map. The node's definition has the order that reads well.
  defp ordered_controls(%{"controls" => controls} = data) do
    fields = data |> definition_fields() |> Enum.map(&to_string(&1.name))

    Enum.sort_by(controls, fn {key, _control} ->
      Enum.find_index(fields, &(&1 == key)) || length(fields)
    end)
  end

  defp node_icon(nil), do: "hero-cube"

  defp node_icon(type) do
    case HeddleNodes.Nodes.get_node(type) do
      nil -> "hero-cube"
      node -> node.icon || "hero-cube"
    end
  end
end
