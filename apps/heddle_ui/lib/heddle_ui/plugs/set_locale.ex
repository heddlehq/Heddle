defmodule HeddleUI.Plugs.SetLocale do
  @moduledoc """
  Picks the language of the interface: the one a `?locale=` asks for, then the one the
  signed-in person chose in their preferences, then the session's, then the browser's.

  A person chooses theirs at `/users/preferences`, see `HeddleUI.UserLive.Preferences`.
  """

  import Plug.Conn

  @supported_locales Gettext.known_locales(HeddleUI.Gettext)

  @doc "The languages the interface has."
  def supported_locales, do: @supported_locales

  def init(_options), do: nil

  def call(conn, _options) do
    scope = conn.assigns[:current_scope]
    browser = extract_from_header(get_req_header(conn, "accept-language"))

    # Someone signed in who chose no language gets the browser's, not what the session
    # kept from before.
    locale =
      supported(conn.params["locale"]) || user_locale(scope) ||
        if(signed_in?(scope), do: browser) || supported(get_session(conn, :locale)) || browser

    if locale do
      Gettext.put_locale(HeddleUI.Gettext, locale)

      conn
      |> put_session(:locale, locale)
      |> assign(:locale, locale)
    else
      assign(conn, :locale, Gettext.get_locale(HeddleUI.Gettext))
    end
  end

  defp supported(locale) when locale in @supported_locales, do: locale
  defp supported(_locale), do: nil

  defp user_locale(%{user: %{locale: locale}}), do: supported(locale)
  defp user_locale(_scope), do: nil

  defp signed_in?(%{user: %{}}), do: true
  defp signed_in?(_scope), do: false

  defp extract_from_header([header | _]) when is_binary(header) do
    header
    |> String.split(",")
    |> Enum.map(&String.split(&1, ";"))
    |> Enum.map(&List.first/1)
    |> Enum.map(&String.split(&1, "-"))
    |> Enum.map(&List.first/1)
    |> Enum.map(&String.trim/1)
    |> Enum.find(&(&1 in @supported_locales))
  end

  defp extract_from_header(_), do: nil

  # LiveView Hook
  def on_mount(:default, params, session, socket) do
    locale =
      supported(params["locale"]) || user_locale(socket.assigns[:current_scope]) ||
        supported(session["locale"]) || Gettext.get_locale(HeddleUI.Gettext)

    Gettext.put_locale(HeddleUI.Gettext, locale)
    {:cont, Phoenix.Component.assign(socket, :locale, locale)}
  end
end
