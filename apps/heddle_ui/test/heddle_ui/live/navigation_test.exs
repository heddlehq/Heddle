defmodule HeddleUI.NavigationTest do
  use HeddleUI.ConnCase, async: true

  import Phoenix.LiveViewTest
  import HeddleCore.AccountsFixtures
  import HeddleCore.FlowsFixtures

  alias HeddleCore.Accounts.Scope
  alias HeddleUI.Layouts

  describe "live navigation" do
    setup %{conn: conn} do
      admin = system_admin_fixture()
      %{admin: admin, conn: log_in_user(conn, admin)}
    end

    test "moves between the dashboard and admin pages without a full reload", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert {:ok, view, _html} = live_redirect(view, to: ~p"/flows")
      assert {:ok, view, _html} = live_redirect(view, to: ~p"/")
      assert {:ok, view, _html} = live_redirect(view, to: ~p"/executions")
      assert {:ok, view, _html} = live_redirect(view, to: ~p"/api-keys")
      assert {:ok, view, _html} = live_redirect(view, to: ~p"/users")
      assert {:ok, _view, _html} = live_redirect(view, to: ~p"/")
    end

    test "reaches the flow editor from the dashboard without a full reload", %{
      admin: admin,
      conn: conn
    } do
      flow = flow_fixture(%{user_id: admin.id})
      {:ok, view, _html} = live(conn, ~p"/")

      assert {:ok, _view, _html} = live_redirect(view, to: ~p"/flows/#{flow.id}")
    end
  end

  describe "admin pages reached by live navigation" do
    test "send a regular user back to the dashboard", %{conn: conn} do
      conn = log_in_user(conn, user_fixture())

      for path <- [
            ~p"/flows",
            ~p"/flows/new/ai",
            ~p"/ai",
            ~p"/executions",
            ~p"/api-keys",
            ~p"/users"
          ] do
        {:ok, view, _html} = live(conn, ~p"/")

        assert {:error, {:redirect, %{to: "/"}}} = live_redirect(view, to: path)
      end
    end
  end

  describe "sidebar" do
    setup %{conn: conn} do
      %{conn: log_in_user(conn, system_admin_fixture())}
    end

    for {path, id} <- [
          {"/", "nav-dashboard"},
          {"/flows", "nav-flows"},
          {"/executions", "nav-executions"},
          {"/api-keys", "nav-api-keys"},
          {"/users", "nav-users"}
        ] do
      test "marks only #{id} as the current page on #{path}", %{conn: conn} do
        {:ok, view, _html} = live(conn, unquote(path))

        assert has_element?(view, "##{unquote(id)}[aria-current=page]")
        assert view |> render() |> LazyHTML.from_fragment() |> current_pages() == 1
      end
    end

    test "keeps Flows active on the AI creator" do
      scope = Scope.for_user(system_admin_fixture())

      html =
        render_component(&Layouts.app/1,
          flash: %{},
          current_scope: scope,
          current_path: "/flows/new/ai"
        )

      document = LazyHTML.from_fragment(html)

      assert document |> LazyHTML.query("#nav-flows[aria-current=page]") |> Enum.count() == 1
      assert current_pages(document) == 1
    end

    test "marks LLM & Agents on its own page" do
      scope = Scope.for_user(system_admin_fixture())

      html =
        render_component(&Layouts.app/1,
          flash: %{},
          current_scope: scope,
          current_path: "/ai"
        )

      document = LazyHTML.from_fragment(html)

      assert document |> LazyHTML.query("#nav-ai[aria-current=page]") |> Enum.count() == 1
      assert current_pages(document) == 1
    end

    test "keeps Flows active on a flow page" do
      scope = Scope.for_user(system_admin_fixture())

      html =
        render_component(&Layouts.app/1,
          flash: %{},
          current_scope: scope,
          current_path: "/flows/7"
        )

      document = LazyHTML.from_fragment(html)

      assert document |> LazyHTML.query("#nav-flows[aria-current=page]") |> Enum.count() == 1
    end

    test "marks nothing on a page outside the menu", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/settings")

      assert view |> render() |> LazyHTML.from_fragment() |> current_pages() == 0
    end

    test "follows the page after live navigation", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      {:ok, view, _html} = live_redirect(view, to: ~p"/flows")

      assert has_element?(view, "#nav-flows[aria-current=page]")
      refute has_element?(view, "#nav-dashboard[aria-current=page]")
    end
  end

  defp current_pages(document) do
    document |> LazyHTML.query("[aria-current=page]") |> Enum.count()
  end
end
