defmodule HeddleUI.WorkspaceLive.ShowTest do
  use HeddleUI.ConnCase, async: true

  import Phoenix.LiveViewTest
  import HeddleCore.AccountsFixtures

  alias HeddleCore.Workspaces

  setup %{conn: conn} do
    admin = user_fixture()
    workspace = workspace_fixture(admin, name: "Marketing")
    %{conn: log_in_user(conn, admin), admin: admin, workspace: workspace}
  end

  defp as(workspace, role) do
    user = user_fixture()
    member_fixture(workspace, user, role)
    {user, Phoenix.ConnTest.build_conn() |> log_in_user(user)}
  end

  test "someone in no workspace is sent back" do
    conn = Phoenix.ConnTest.build_conn() |> log_in_user(user_fixture())

    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/workspace")
  end

  test "an admin adds someone with an account and changes their role", %{
    conn: conn,
    admin: admin,
    workspace: workspace
  } do
    person = user_fixture()
    {:ok, lv, _html} = live(conn, ~p"/workspace")

    lv
    |> form("#add-member-form", member: %{identifier: person.email, role: "viewer"})
    |> render_submit()

    members = Workspaces.list_members(HeddleCore.Accounts.Scope.for_user(admin), workspace)
    member = Enum.find(members, &(&1.user_id == person.id))
    assert member.role == "viewer"
    assert has_element?(lv, "#member-#{member.id}")

    lv
    |> form("#member-role-#{member.id}", %{"member_id" => member.id, "role" => "operator"})
    |> render_change()

    assert Workspaces.role_of(person, workspace.id) == "operator"
  end

  test "an admin gets an invite link for a role", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/workspace")

    lv |> form("#invite-form", invite: %{role: "operator"}) |> render_submit()

    assert has_element?(lv, "input#invite-url")
    assert render(lv) =~ "Joins Marketing as Operator"
    assert has_element?(lv, "#open-invites")
  end

  test "the last admin can't step down", %{conn: conn, admin: admin, workspace: workspace} do
    member = HeddleCore.Repo.get_by!(HeddleCore.Workspaces.Member, user_id: admin.id)
    {:ok, lv, _html} = live(conn, ~p"/workspace")

    html =
      lv
      |> form("#member-role-#{member.id}", %{"member_id" => member.id, "role" => "viewer"})
      |> render_change()

    assert html =~ "at least one admin"
    assert Workspaces.role_of(admin, workspace.id) == "admin"
  end

  test "a viewer sees the members, with nothing to change", %{workspace: workspace} do
    {_viewer, conn} = as(workspace, "viewer")
    {:ok, lv, html} = live(conn, ~p"/workspace")

    assert html =~ "Marketing"
    refute has_element?(lv, "#add-member-form")
    refute has_element?(lv, "#invite-form")
    refute has_element?(lv, "#workspace-rename-form")
    refute has_element?(lv, "select[name='role']")
  end

  test "a member can leave", %{workspace: workspace} do
    {viewer, conn} = as(workspace, "viewer")
    member = HeddleCore.Repo.get_by!(HeddleCore.Workspaces.Member, user_id: viewer.id)
    {:ok, lv, _html} = live(conn, ~p"/workspace")

    lv |> element("#remove-member-#{member.id}") |> render_click()

    assert_redirect(lv, ~p"/")
    assert Workspaces.role_of(viewer, workspace.id) == nil
  end

  test "an admin renames the workspace", %{conn: conn, workspace: workspace} do
    {:ok, lv, _html} = live(conn, ~p"/workspace")

    lv |> form("#workspace-rename-form", workspace: %{name: "Growth"}) |> render_submit()

    assert render(lv) =~ "Growth"
    assert Workspaces.get_workspace(workspace.id).name == "Growth"
  end

  test "only system admins see how to delete it", %{conn: conn, workspace: workspace} do
    {:ok, lv, _html} = live(conn, ~p"/workspace")
    refute has_element?(lv, "#workspace-danger-zone")

    admin = system_admin_fixture()

    {:ok, _scope} =
      Workspaces.switch_workspace(HeddleCore.Accounts.Scope.for_user(admin), workspace)

    {:ok, lv, _html} = live(Phoenix.ConnTest.build_conn() |> log_in_user(admin), ~p"/workspace")

    lv |> form("#delete-workspace-form", delete: %{name: "wrong"}) |> render_submit()
    assert Workspaces.get_workspace(workspace.id)

    lv |> form("#delete-workspace-form", delete: %{name: "Marketing"}) |> render_submit()
    assert_redirect(lv, ~p"/workspaces")
    refute Workspaces.get_workspace(workspace.id)
  end
end
