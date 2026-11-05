defmodule HeddleUI.AILive.Index do
  use HeddleUI, :live_view

  on_mount {HeddleUI.UserAuth, :require_system_admin}

  alias HeddleAI.LLM

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("LLM & Agents"))
     |> assign(:llm, LLM.status())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 md:p-8 w-full max-w-4xl mx-auto space-y-8">
      <div>
        <div class="flex items-center gap-3">
          <h1 class="text-2xl font-bold text-gray-900 dark:text-white">{gettext("LLM & Agents")}</h1>
          <span class="px-2.5 py-0.5 rounded-full text-xs font-medium bg-amber-100 dark:bg-amber-900/30 text-amber-800 dark:text-amber-300">
            {gettext("System admins only")}
          </span>
        </div>
        <p class="text-sm text-gray-500 dark:text-gray-400 mt-1">
          {gettext("What this instance uses to run the AI features.")}
        </p>
      </div>

      <section
        id="llm-provider"
        class="bg-white dark:bg-slate-900 border border-gray-200 dark:border-slate-800 rounded-xl p-6"
      >
        <div class="flex items-center justify-between gap-4">
          <h2 class="text-base font-semibold text-gray-900 dark:text-white">
            {gettext("LLM provider")}
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
    </div>
    """
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

  defp variables(%{state: :invalid, missing: missing}), do: missing
  defp variables(_llm), do: ~w(HEDDLE_LLM_PROVIDER HEDDLE_LLM_MODEL HEDDLE_LLM_API_KEY)
end
