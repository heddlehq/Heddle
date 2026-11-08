defmodule HeddleUI.UserLive.Preferences do
  @moduledoc """
  The language and theme a person chose, saved with them so they follow them to any
  browser. Each change saves at once: the theme applies in place, and a new language
  reloads the page in it. See `HeddleUI.Plugs.SetLocale` and the root layout.
  """

  use HeddleUI, :live_view

  alias HeddleCore.Accounts
  alias HeddleUI.Plugs.SetLocale

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    {:ok,
     socket
     |> assign(:page_title, gettext("Preferences"))
     |> assign(:locale_choice, user.locale || "")
     |> assign(:theme_choice, user.theme || browser_theme(socket))}
  end

  defp browser_theme(socket) do
    case connected?(socket) && get_connect_params(socket)["theme"] do
      theme when theme in ["system", "light", "dark"] -> theme
      _other -> "dark"
    end
  end

  @impl true
  def handle_event("change_locale", %{"locale" => locale}, socket) do
    case save(socket, %{"locale" => locale}) do
      {:ok, _user} ->
        {:noreply, redirect(socket, to: ~p"/users/preferences")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, gettext("This language isn't available."))}
    end
  end

  def handle_event("change_theme", %{"theme" => theme}, socket) do
    case save(socket, %{"theme" => theme}) do
      {:ok, user} ->
        scope = %{socket.assigns.current_scope | user: user}

        {:noreply,
         socket
         |> assign(current_scope: scope, theme_choice: theme)
         |> push_event("set-theme", %{theme: theme})}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, gettext("This theme isn't available."))}
    end
  end

  defp save(socket, attrs) do
    Accounts.update_user_preferences(socket.assigns.current_scope.user, attrs,
      locales: SetLocale.supported_locales()
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 md:p-8 w-full max-w-3xl mx-auto space-y-6">
      <div>
        <h1 class="text-2xl font-bold text-gray-900 dark:text-white">{gettext("Preferences")}</h1>
        <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
          {gettext("How Heddle looks for you, on any browser you sign in to.")}
        </p>
      </div>

      <section
        id="preferences-language"
        class="rounded-xl border border-gray-200 bg-white p-6 shadow-sm dark:border-slate-800 dark:bg-slate-900"
      >
        <h2 class="text-base font-semibold text-gray-900 dark:text-white">{gettext("Language")}</h2>
        <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
          {gettext("The language of menus, buttons and messages.")}
        </p>
        <form id="locale-form" phx-change="change_locale" class="mt-4 max-w-xs">
          <label for="locale-select" class="sr-only">{gettext("Language")}</label>
          <div class="relative">
            <select
              id="locale-select"
              name="locale"
              class="w-full appearance-none rounded-lg border border-gray-200 bg-gray-50 px-4 py-2.5 pr-10 text-sm text-gray-900 transition-colors hover:border-gray-300 focus:border-primary focus:outline-none focus:ring-2 focus:ring-primary/20 dark:border-slate-700 dark:bg-slate-800 dark:text-gray-100 dark:hover:border-slate-600"
            >
              <option value="" selected={@locale_choice == ""}>
                {gettext("Same as the browser")}
              </option>
              <option value="en" selected={@locale_choice == "en"}>English</option>
              <option value="pt_BR" selected={@locale_choice == "pt_BR"}>Português (Brasil)</option>
            </select>
            <.icon
              name="hero-chevron-down"
              class="pointer-events-none absolute right-3 top-1/2 size-4 -translate-y-1/2 text-gray-400"
            />
          </div>
        </form>
      </section>

      <section
        id="preferences-theme"
        class="rounded-xl border border-gray-200 bg-white p-6 shadow-sm dark:border-slate-800 dark:bg-slate-900"
      >
        <h2 class="text-base font-semibold text-gray-900 dark:text-white">{gettext("Theme")}</h2>
        <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
          {gettext("Light, dark, or whichever your device uses.")}
        </p>
        <div class="mt-4 grid gap-3 sm:grid-cols-3" role="radiogroup" aria-label={gettext("Theme")}>
          <.theme_option
            value="system"
            current={@theme_choice}
            icon="hero-computer-desktop"
            label={gettext("System")}
          />
          <.theme_option
            value="light"
            current={@theme_choice}
            icon="hero-sun"
            label={gettext("Light")}
          />
          <.theme_option
            value="dark"
            current={@theme_choice}
            icon="hero-moon"
            label={gettext("Dark")}
          />
        </div>
      </section>
    </div>
    """
  end

  attr :value, :string, required: true
  attr :current, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true

  defp theme_option(assigns) do
    ~H"""
    <button
      id={"theme-#{@value}"}
      type="button"
      role="radio"
      aria-checked={to_string(@value == @current)}
      phx-click="change_theme"
      phx-value-theme={@value}
      class={[
        "group flex items-center gap-3 rounded-lg border px-4 py-3 text-left text-sm font-medium transition-all duration-150",
        if(@value == @current,
          do: "border-primary bg-primary/5 text-gray-900 ring-2 ring-primary/20 dark:text-white",
          else:
            "border-gray-200 text-gray-700 hover:border-gray-300 hover:bg-gray-50 dark:border-slate-700 dark:text-gray-300 dark:hover:border-slate-600 dark:hover:bg-slate-800"
        )
      ]}
    >
      <span class={[
        "flex size-8 items-center justify-center rounded-md transition-colors",
        if(@value == @current,
          do: "bg-primary text-primary-content",
          else:
            "bg-gray-100 text-gray-500 group-hover:text-gray-700 dark:bg-slate-800 dark:text-gray-400"
        )
      ]}>
        <.icon name={@icon} class="size-4" />
      </span>
      {@label}
      <.icon
        :if={@value == @current}
        name="hero-check-circle-mini"
        class="ml-auto size-5 text-primary"
      />
    </button>
    """
  end
end
