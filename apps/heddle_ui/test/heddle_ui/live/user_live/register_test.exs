defmodule HeddleUI.UserLive.RegisterTest do
  use HeddleUI.ConnCase, async: true

  import Phoenix.LiveViewTest
  import HeddleCore.AccountsFixtures

  describe "mount /users/register/:token" do
    test "redirects to log-in with flash when token is invalid", %{conn: conn} do
      assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/users/register/invalid-token")
      assert path == ~p"/users/log-in"
    end

    test "redirects when invite is already used", %{conn: conn} do
      invite = invite_fixture(used_at: DateTime.utc_now())
      assert {:error, {:redirect, _}} = live(conn, ~p"/users/register/#{invite.token}")
    end

    test "redirects when invite is expired", %{conn: conn} do
      invite =
        invite_fixture(expires_at: DateTime.add(DateTime.utc_now(), -1, :day))

      assert {:error, {:redirect, _}} = live(conn, ~p"/users/register/#{invite.token}")
    end

    test "renders registration form for valid token", %{conn: conn} do
      invite = invite_fixture()

      {:ok, _lv, html} = live(conn, ~p"/users/register/#{invite.token}")

      assert html =~ "Create your account"
      assert html =~ "Username"
      assert html =~ "Email"
      assert html =~ "Password"
    end

    test "submitting form creates user and marks invite used", %{conn: conn} do
      invite = invite_fixture()

      attrs = %{
        username: "newuser",
        email: "newuser@example.com",
        password: "password123",
        password_confirmation: "password123"
      }

      {:ok, lv, _html} = live(conn, ~p"/users/register/#{invite.token}")

      form = form(lv, "#register_form", user: attrs)
      render_submit(form)

      assert_redirect(lv, ~p"/users/log-in")
      assert HeddleCore.Accounts.get_user_by_email(attrs.email)
      used_invite = HeddleCore.Repo.get!(HeddleCore.Accounts.Invite, invite.id)
      refute HeddleCore.Accounts.Invite.valid?(used_invite)
    end
  end
end
