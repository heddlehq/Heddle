defmodule HeddleUI.UserLive.PreferencesTest do
  use HeddleUI.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias HeddleCore.Accounts

  setup :register_and_log_in_user

  test "saves the theme and applies it in place", %{conn: conn, user: user} do
    {:ok, lv, _html} = live(conn, ~p"/users/preferences")

    lv |> element("#theme-light") |> render_click()

    assert_push_event(lv, "set-theme", %{theme: "light"})
    assert Accounts.get_user!(user.id).theme == "light"
    assert has_element?(lv, ~s(#theme-light[aria-checked="true"]))
  end

  test "saves the language and reloads in it", %{conn: conn, user: user} do
    {:ok, lv, _html} = live(conn, ~p"/users/preferences")

    assert {:error, {:redirect, %{to: "/users/preferences"}}} =
             lv |> form("#locale-form", locale: "pt_BR") |> render_change()

    assert Accounts.get_user!(user.id).locale == "pt_BR"

    {:ok, _lv, html} = live(conn, ~p"/users/preferences")
    assert html =~ ~s(lang="pt-BR")
  end

  test "the page carries the chosen theme, and the language beats the session", %{
    conn: conn,
    user: user
  } do
    {:ok, _user} =
      Accounts.update_user_preferences(user, %{"theme" => "system", "locale" => "pt_BR"},
        locales: ["en", "pt_BR"]
      )

    html =
      conn
      |> Plug.Conn.put_session(:locale, "en")
      |> get(~p"/users/preferences")
      |> html_response(200)

    assert html =~ ~s(data-user-theme="system")
    assert html =~ ~s(lang="pt-BR")
  end

  test "with no language chosen, the browser's wins over the session", %{conn: conn} do
    html =
      conn
      |> Plug.Conn.put_session(:locale, "pt_BR")
      |> Plug.Conn.put_req_header("accept-language", "en-US,en;q=0.9")
      |> get(~p"/users/preferences")
      |> html_response(200)

    assert html =~ ~s(lang="en")
  end

  test "with no theme saved, marks the one this browser shows", %{conn: conn} do
    {:ok, lv, _html} =
      conn |> put_connect_params(%{"theme" => "light"}) |> live(~p"/users/preferences")

    assert has_element?(lv, ~s(#theme-light[aria-checked="true"]))
  end
end
