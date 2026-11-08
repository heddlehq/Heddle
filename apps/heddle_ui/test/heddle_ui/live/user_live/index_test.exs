defmodule HeddleUI.UserLive.IndexTest do
  use HeddleUI.ConnCase, async: true

  import Phoenix.LiveViewTest
  import HeddleCore.AccountsFixtures

  describe "mount /users" do
    test "redirects non-admin to root with flash", %{conn: conn} do
      user = user_fixture()

      assert {:error, {:redirect, %{to: path}}} =
               conn
               |> log_in_user(user)
               |> live(~p"/users")

      assert path == ~p"/"
    end

    test "renders users page for system admin", %{conn: conn} do
      admin = system_admin_fixture()
      _other = user_fixture()

      {:ok, _lv, html} =
        conn
        |> log_in_user(admin)
        |> live(~p"/users")

      assert html =~ "Users"
      assert html =~ "Invite link"
      assert html =~ admin.username
    end

    test "generate_invite creates and shows invite link", %{conn: conn} do
      admin = system_admin_fixture()

      {:ok, lv, _html} =
        conn
        |> log_in_user(admin)
        |> live(~p"/users")

      workspace = ensure_workspace(admin)

      lv
      |> form("#user-invite-form", invite: %{workspace_id: workspace.id, role: "operator"})
      |> render_submit()

      assert has_element?(lv, "input#invite-url")
      assert render(lv) =~ "/users/register/"

      assert [%{role: "operator"}] =
               HeddleCore.Accounts.list_open_invites(
                 HeddleCore.Accounts.Scope.for_user(admin),
                 workspace
               )
    end
  end
end
