defmodule HeddleUI.WorkspaceLive.IndexTest do
  use HeddleUI.ConnCase, async: true

  import Phoenix.LiveViewTest
  import HeddleCore.AccountsFixtures

  alias HeddleCore.Accounts.Scope

  test "is only for system admins", %{conn: conn} do
    conn = log_in_user(conn, user_scope_fixture().user)

    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/workspaces")
  end

  test "creates a workspace and opens it", %{conn: conn} do
    admin = system_admin_fixture()
    {:ok, lv, _html} = conn |> log_in_user(admin) |> live(~p"/workspaces")

    lv |> form("#workspace-form", workspace: %{name: "Finance"}) |> render_submit()

    assert_redirect(lv, ~p"/workspace")

    assert %Scope{workspace: %{name: "Finance"}, role: "admin"} =
             Scope.for_user(HeddleCore.Repo.reload!(admin))
  end

  test "lists every workspace, with its members and flows", %{conn: conn} do
    other = workspace_fixture(user_fixture(), name: "Someone else's")
    {:ok, lv, html} = conn |> log_in_user(system_admin_fixture()) |> live(~p"/workspaces")

    assert html =~ "Someone else&#39;s"
    assert has_element?(lv, "#workspace-#{other.id}")
  end
end
