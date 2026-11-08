defmodule HeddleUI.SidebarTest do
  use HeddleUI.ConnCase, async: true

  import Phoenix.LiveViewTest
  import HeddleCore.AccountsFixtures

  test "groups the pages, and leaves language and theme to the preferences", %{conn: conn} do
    user = user_fixture()
    workspace_fixture(user)
    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/")

    assert has_element?(lv, "#nav-group-main #nav-spool")
    assert has_element?(lv, "#nav-group-workspace #nav-credentials")
    refute has_element?(lv, "#nav-group-instance")
    refute has_element?(lv, "#locale-select")
    assert has_element?(lv, ~s(#user-menu-preferences[href="/users/preferences"]))
    assert has_element?(lv, ~s(#user-menu-settings[href="/users/settings"]))
  end

  test "a system admin also sees the instance", %{conn: conn} do
    {:ok, lv, _html} = conn |> log_in_user(system_admin_fixture()) |> live(~p"/spool")

    assert has_element?(lv, "#nav-group-instance #nav-users")
    assert has_element?(lv, ~s(#nav-spool[aria-current="page"]))
  end
end
