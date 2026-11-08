defmodule HeddleUI.AILive.Index do
  use HeddleUI, :live_view

  on_mount {HeddleUI.UserAuth, :require_system_admin}

  alias HeddleAI.ClaudeAgent
  alias HeddleAI.LLM
  alias HeddleCore.Credentials
  alias HeddleCore.Settings
  alias HeddleUI.AILive.Defaults
  alias HeddleUI.Terminal

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("AI"))
     |> assign(:llm, LLM.status())
     |> assign(:ai_credentials, ai_credentials())
     |> assign_defaults(Defaults.to_form_params(Settings.ai_defaults()))
     |> assign(:agent_enabled, Settings.claude_agent_enabled?())
     |> assign(:terminal_enabled, Settings.terminal_enabled?())
     |> assign(:mcp_command, mcp_command())
     |> assign_binary_form(Settings.claude_binary() || "")
     |> assign_agent()}
  end

  defp assign_agent(socket) do
    agent = ClaudeAgent.status()

    socket
    |> assign(:agent, agent)
    |> assign(:terminal_supported, Terminal.supported?())
    |> assign_async(:agent_version, fn -> {:ok, %{agent_version: version(agent)}} end)
  end

  defp assign_binary_form(socket, path) do
    assign(socket, :binary_form, to_form(%{"path" => path}, as: :claude))
  end

  @impl true
  def handle_event("change_defaults", %{"ai" => params} = event, socket) do
    {:noreply, assign_defaults(socket, Defaults.reset_model(params, event["_target"]))}
  end

  def handle_event("save_defaults", %{"ai" => params}, socket) do
    case Settings.set_ai_defaults(Defaults.to_settings(params)) do
      {:ok, _setting} ->
        {:noreply,
         socket
         |> assign_defaults(params)
         |> put_flash(:info, gettext("AI settings saved."))}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, gettext("Could not save this setting."))}
    end
  end

  def handle_event("save_claude_binary", %{"claude" => %{"path" => path}}, socket) do
    path = path |> String.trim() |> Path.expand() |> then(&if(path == "", do: "", else: &1))

    with :ok <- check_binary(path),
         {:ok, _setting} <- Settings.set_claude_binary(path) do
      {:noreply,
       socket
       |> assign_binary_form(path)
       |> assign_agent()
       |> put_flash(:info, gettext("AI settings saved."))}
    else
      {:error, :not_executable} ->
        {:noreply,
         socket
         |> assign_binary_form(path)
         |> put_flash(:error, gettext("There is no program at this path."))}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, gettext("Could not save this setting."))}
    end
  end

  def handle_event("toggle_terminal", _params, socket) do
    enabled = not socket.assigns.terminal_enabled

    cond do
      enabled and not socket.assigns.terminal_supported ->
        {:noreply, put_flash(socket, :error, gettext("The Terminal is not available here."))}

      match?({:ok, _setting}, Settings.set_terminal_enabled(enabled)) ->
        {:noreply, assign(socket, :terminal_enabled, enabled)}

      true ->
        {:noreply, put_flash(socket, :error, gettext("Could not save this setting."))}
    end
  end

  def handle_event("toggle_claude_agent", _params, socket) do
    enabled = not socket.assigns.agent_enabled

    case set_agent_enabled(socket.assigns.agent, enabled) do
      {:ok, _setting} ->
        {:noreply, assign(socket, :agent_enabled, enabled)}

      :unavailable ->
        {:noreply, put_flash(socket, :error, gettext("The Claude Agent is not available."))}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, gettext("Could not save this setting."))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 md:p-8 w-full max-w-4xl mx-auto space-y-8">
      <div>
        <div class="flex items-center gap-3">
          <h1 class="text-2xl font-bold text-gray-900 dark:text-white">{gettext("AI")}</h1>
          <span class="px-2.5 py-0.5 rounded-full text-xs font-medium bg-amber-100 dark:bg-amber-900/30 text-amber-800 dark:text-amber-300">
            {gettext("System admins only")}
          </span>
        </div>
        <p class="text-sm text-gray-500 dark:text-gray-400 mt-1">
          {gettext("What this instance uses to run the AI features.")}
        </p>
      </div>

      <Defaults.defaults_section form={@defaults_form} credentials={@ai_credentials} />

      <section
        id="llm-provider"
        class="bg-white dark:bg-slate-900 border border-gray-200 dark:border-slate-800 rounded-xl p-6"
      >
        <div class="flex items-center justify-between gap-4">
          <h2 class="text-base font-semibold text-gray-900 dark:text-white">
            {gettext("LLM from the environment")}
          </h2>
          <.status_badge state={@llm.state} />
        </div>

        <%= if @llm.state == :ready do %>
          <dl class="mt-4 grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div>
              <dt class="text-xs text-gray-500 dark:text-gray-400">{gettext("Provider")}</dt>
              <dd id="llm-provider-name" class="font-mono text-sm text-gray-900 dark:text-white">
                {@llm.provider}
              </dd>
            </div>
            <div>
              <dt class="text-xs text-gray-500 dark:text-gray-400">{gettext("Model")}</dt>
              <dd id="llm-model" class="font-mono text-sm text-gray-900 dark:text-white">
                {@llm.model}
              </dd>
            </div>
          </dl>
          <p
            :if={@llm.source == :openai_legacy}
            id="llm-legacy-notice"
            class="mt-4 text-xs text-gray-500 dark:text-gray-400"
          >
            {gettext("Read from OPENAI_API_KEY. Set the HEDDLE_LLM_* variables to change provider.")}
          </p>
        <% else %>
          <p class="mt-3 text-sm text-gray-500 dark:text-gray-400">
            {gettext("The provider comes from the environment. Set these variables and restart:")}
          </p>
          <ul id="llm-variables" class="mt-3 space-y-1">
            <li
              :for={variable <- variables(@llm)}
              class="font-mono text-sm text-gray-900 dark:text-white"
            >
              {variable}
            </li>
          </ul>
        <% end %>
      </section>

      <section
        id="claude-agent"
        class="bg-white dark:bg-slate-900 border border-gray-200 dark:border-slate-800 rounded-xl p-6"
      >
        <div class="flex items-center justify-between gap-4">
          <div>
            <h2 class="text-base font-semibold text-gray-900 dark:text-white">
              {gettext("Claude Agent")}
            </h2>
            <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
              {gettext("Copilot in the editor chat. It can read, edit and run your flows.")}
            </p>
          </div>
          <.switch
            id="claude-agent-toggle"
            on={agent_on?(@agent, @agent_enabled)}
            disabled={@agent.state != :ready}
            label={gettext("Use in the editor chat")}
            click="toggle_claude_agent"
          />
        </div>

        <dl class="mt-4 grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div>
            <dt class="text-xs text-gray-500 dark:text-gray-400">{gettext("Binary")}</dt>
            <dd id="claude-agent-binary" class="font-mono text-sm text-gray-900 dark:text-white">
              <%= if @agent.binary do %>
                {gettext("Found")}
                <span :if={@agent_version.ok? && @agent_version.result}>
                  ({@agent_version.result})
                </span>
              <% else %>
                {gettext("Not found")}
              <% end %>
            </dd>
          </div>
          <div>
            <dt class="text-xs text-gray-500 dark:text-gray-400">{gettext("API key")}</dt>
            <dd id="claude-agent-key" class="font-mono text-sm text-gray-900 dark:text-white">
              {if @agent.key?, do: gettext("Set"), else: gettext("Not set")}
            </dd>
          </div>
        </dl>

        <.form
          for={@binary_form}
          id="claude-binary-form"
          phx-submit="save_claude_binary"
          class="mt-4 flex items-end gap-2"
        >
          <div class="min-w-0 flex-1">
            <.input
              field={@binary_form[:path]}
              type="text"
              label={gettext("Path of the claude program")}
              placeholder={gettext("Found automatically when empty")}
            />
          </div>
          <.button id="claude-binary-save" type="submit" variant="ghost" class="mb-2">
            {gettext("Save")}
          </.button>
        </.form>

        <p
          :if={@agent.state != :ready}
          id="claude-agent-help"
          class="mt-2 text-xs text-gray-500 dark:text-gray-400"
        >
          {agent_help(@agent.state, @terminal_supported)}
        </p>
      </section>

      <section
        id="terminal-settings"
        class="bg-white dark:bg-slate-900 border border-gray-200 dark:border-slate-800 rounded-xl p-6"
      >
        <div class="flex items-center justify-between gap-4">
          <div>
            <h2 class="text-base font-semibold text-gray-900 dark:text-white">
              {gettext("Terminal")}
            </h2>
            <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
              {gettext(
                "Runs Claude Code in the flow editor, connected to your flows. It works with your Claude subscription, and you sign in inside it."
              )}
            </p>
          </div>
          <.switch
            id="terminal-toggle"
            on={@terminal_supported and @terminal_enabled}
            disabled={not @terminal_supported}
            label={gettext("Show the Terminal in the editor")}
            click="toggle_terminal"
          />
        </div>
        <p
          :if={not @terminal_supported}
          id="terminal-help"
          class="mt-4 text-xs text-gray-500 dark:text-gray-400"
        >
          {gettext(
            "It needs Heddle installed on your own machine, with the claude program. It can run commands there, so it isn't offered on a shared server."
          )}
        </p>
      </section>

      <section
        id="mcp-server"
        class="bg-white dark:bg-slate-900 border border-gray-200 dark:border-slate-800 rounded-xl p-6"
      >
        <h2 class="text-base font-semibold text-gray-900 dark:text-white">
          {gettext("MCP server")}
        </h2>
        <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
          {gettext("Connect an external agent to read, edit and run your flows.")}
        </p>
        <pre
          id="mcp-command"
          class="mt-4 overflow-x-auto rounded-lg bg-gray-50 dark:bg-slate-950 border border-gray-200 dark:border-slate-800 p-3 font-mono text-xs text-gray-900 dark:text-gray-100"
        >{@mcp_command}</pre>
        <p class="mt-3 text-xs text-gray-500 dark:text-gray-400">
          {gettext(
            "External agents run flows without asking for confirmation: only the scopes of the API key limit them."
          )}
          <.link
            id="mcp-api-keys-link"
            navigate={~p"/api-keys"}
            class="text-primary hover:underline"
          >
            {gettext("Manage API keys")}
          </.link>
        </p>
      </section>
    </div>
    """
  end

  defp assign_defaults(socket, params) do
    assign(socket, :defaults_form, to_form(params, as: :ai))
  end

  defp ai_credentials do
    for %{kind: "ai", name: name} <- Credentials.list_shared_credentials(), do: name
  end

  attr :state, :atom, required: true

  defp status_badge(assigns) do
    ~H"""
    <span
      id="llm-status"
      data-state={@state}
      class={[
        "px-2.5 py-0.5 rounded-full text-xs font-medium",
        @state == :ready &&
          "bg-emerald-100 dark:bg-emerald-900/30 text-emerald-800 dark:text-emerald-300",
        @state == :invalid && "bg-rose-100 dark:bg-rose-900/30 text-rose-800 dark:text-rose-300",
        @state == :not_configured &&
          "bg-gray-100 dark:bg-slate-800 text-gray-700 dark:text-gray-300"
      ]}
    >
      {status_label(@state)}
    </span>
    """
  end

  defp status_label(:ready), do: gettext("Active")
  defp status_label(:invalid), do: gettext("Incomplete")
  defp status_label(:not_configured), do: gettext("Not configured")

  defp set_agent_enabled(%{state: :ready}, enabled) do
    Settings.set_claude_agent_enabled(enabled)
  end

  defp set_agent_enabled(_agent, false), do: Settings.set_claude_agent_enabled(false)
  defp set_agent_enabled(_agent, true), do: :unavailable

  defp agent_on?(agent, enabled), do: agent.state == :ready and enabled

  defp version(%{binary: nil}), do: nil
  defp version(%{binary: binary}), do: ClaudeAgent.version(binary)

  defp agent_help(:missing_binary, _terminal?) do
    gettext("Install claude on this server, or set its path above.")
  end

  defp agent_help(:missing_key, true) do
    gettext(
      "Set HEDDLE_CLAUDE_API_KEY. To use a Claude subscription, turn on the Terminal below."
    )
  end

  defp agent_help(:missing_key, false) do
    gettext("Set HEDDLE_CLAUDE_API_KEY. Claude subscriptions can't be used here.")
  end

  defp check_binary(""), do: :ok

  defp check_binary(path) do
    if File.regular?(path) and executable?(path), do: :ok, else: {:error, :not_executable}
  end

  defp executable?(path) do
    case File.stat(path) do
      {:ok, %{mode: mode}} -> Bitwise.band(mode, 0o111) != 0
      {:error, _reason} -> false
    end
  end

  attr :id, :string, required: true
  attr :on, :boolean, required: true
  attr :disabled, :boolean, required: true
  attr :label, :string, required: true
  attr :click, :string, required: true

  defp switch(assigns) do
    ~H"""
    <button
      id={@id}
      type="button"
      role="switch"
      aria-checked={to_string(@on)}
      aria-label={@label}
      disabled={@disabled}
      phx-click={@click}
      class={[
        "relative inline-flex h-6 w-11 flex-shrink-0 rounded-full transition-colors focus:outline-none focus:ring-2 focus:ring-primary disabled:cursor-not-allowed disabled:opacity-50",
        if(@on, do: "bg-primary", else: "bg-gray-200 dark:bg-slate-700")
      ]}
    >
      <span class={[
        "inline-block h-5 w-5 mt-0.5 rounded-full bg-white shadow transition-transform",
        if(@on, do: "translate-x-[22px]", else: "translate-x-0.5")
      ]} />
    </button>
    """
  end

  defp mcp_command do
    "claude mcp add --transport http heddle #{url(~p"/mcp")} \\\n" <>
      "  --header \"Authorization: Bearer <API key>\""
  end

  defp variables(%{state: :invalid, missing: missing}), do: missing
  defp variables(_llm), do: ~w(HEDDLE_LLM_PROVIDER HEDDLE_LLM_MODEL HEDDLE_LLM_API_KEY)
end
