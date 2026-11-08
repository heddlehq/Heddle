defmodule HeddleUI.SpoolLiveTest do
  use HeddleUI.ConnCase, async: true

  import Phoenix.LiveViewTest
  import HeddleCore.AccountsFixtures

  alias HeddleCore.Spool

  setup %{conn: conn} do
    user = user_fixture()
    workspace = workspace_fixture(user)
    scope = user_scope_fixture(user)
    %{conn: log_in_user(conn, user), scope: scope, workspace: workspace}
  end

  defp as_role(workspace, role) do
    user = user_fixture()
    member_fixture(workspace, user, role)
    Phoenix.ConnTest.build_conn() |> log_in_user(user)
  end

  defp table_fixture(scope) do
    {:ok, table} =
      Spool.create_table(scope, %{
        "name" => "leads",
        "columns" => [%{"name" => "email"}, %{"name" => "score", "type" => "number"}]
      })

    table
  end

  describe "index" do
    test "an empty workspace says so, and an editor creates a table", %{conn: conn, scope: scope} do
      {:ok, lv, _html} = live(conn, ~p"/spool")
      assert has_element?(lv, "#spool-empty")

      assert {:error, {:live_redirect, %{to: to}}} =
               lv |> form("#spool-table-form", table: %{name: "Orders"}) |> render_submit()

      assert [%{name: "Orders"} = table] = Spool.list_tables(scope)
      assert to == ~p"/spool/#{table.id}?tab=columns"
    end

    test "shows the tables, and a taken name", %{conn: conn, scope: scope} do
      table = table_fixture(scope)
      {:ok, lv, _html} = live(conn, ~p"/spool")

      assert has_element?(lv, "#tables-#{table.id}", "leads")

      lv |> form("#spool-table-form", table: %{name: "leads"}) |> render_submit()
      assert render(lv) =~ "is already the name of a table"
    end

    test "a viewer sees tables but can't create one", %{workspace: workspace, scope: scope} do
      table_fixture(scope)
      {:ok, lv, _html} = live(as_role(workspace, "viewer"), ~p"/spool")

      refute has_element?(lv, "#spool-table-form")
      assert has_element?(lv, "#spool-tables a", "leads")
    end
  end

  describe "a table" do
    setup %{scope: scope}, do: %{table: table_fixture(scope)}

    test "of another workspace looks missing", %{table: table} do
      other =
        Phoenix.ConnTest.build_conn() |> log_in_user(user_fixture() |> tap(&workspace_fixture/1))

      assert {:error, {:live_redirect, %{to: "/spool"}}} = live(other, ~p"/spool/#{table.id}")
    end

    test "adds, changes and deletes rows", %{conn: conn, scope: scope, table: table} do
      [email, score] = table.columns
      {:ok, lv, _html} = live(conn, ~p"/spool/#{table.id}")

      lv |> element("#spool-new-row") |> render_click()

      lv
      |> form("#spool-row-form", row: %{email["id"] => "ana@example.com", score["id"] => "x"})
      |> render_submit()

      assert has_element?(lv, "#spool-row-error")

      lv
      |> form("#spool-row-form", row: %{email["id"] => "ana@example.com", score["id"] => "7"})
      |> render_submit()

      assert %{rows: [%{"id" => id, "score" => 7}]} = Spool.list_rows(scope, table)
      assert has_element?(lv, "#spool-row-#{id}", "ana@example.com")

      lv |> element("#spool-row-#{id}") |> render_click()
      lv |> form("#spool-row-form", row: %{score["id"] => ""}) |> render_submit()

      assert %{rows: [%{"score" => nil, "email" => "ana@example.com"}]} =
               Spool.list_rows(scope, table)

      lv |> element("#spool-row-#{id}") |> render_click()
      lv |> element("#spool-row-delete") |> render_click()
      assert %{total: 0} = Spool.list_rows(scope, table)
    end

    test "searches rows through the URL", %{conn: conn, scope: scope, table: table} do
      {:ok, _row} = Spool.insert_row(scope, table, %{"email" => "ana@example.com"})
      {:ok, _row} = Spool.insert_row(scope, table, %{"email" => "bia@example.com"})
      {:ok, lv, _html} = live(conn, ~p"/spool/#{table.id}")

      lv |> form("#spool-search", q: "bia") |> render_change()
      assert_patch(lv, ~p"/spool/#{table.id}?q=bia")
      refute render(lv) =~ "ana@example.com"
    end

    test "renames, adds and removes columns", %{conn: conn, scope: scope, table: table} do
      {:ok, lv, _html} = live(conn, ~p"/spool/#{table.id}?tab=columns")

      lv |> element("#spool-add-column") |> render_click()

      lv
      |> form("#spool-columns-form",
        table: %{
          name: "people",
          columns: %{
            "0" => %{"name" => "mail"},
            "1" => %{"name" => "score", "type" => "number"},
            "2" => %{"name" => "vip", "type" => "boolean"}
          }
        }
      )
      |> render_submit()

      table = Spool.get_table(scope, table.id)
      assert table.name == "people"
      assert Enum.map(table.columns, & &1["name"]) == ["mail", "score", "vip"]

      lv |> element("#spool-column-remove-2") |> render_click()
      lv |> form("#spool-columns-form") |> render_submit()
      assert length(Spool.get_table(scope, table.id).columns) == 2
    end

    test "shows why a type can't change", %{conn: conn, scope: scope, table: table} do
      {:ok, _row} = Spool.insert_row(scope, table, %{"email" => "not a number"})
      {:ok, lv, _html} = live(conn, ~p"/spool/#{table.id}?tab=columns")

      lv
      |> form("#spool-columns-form", table: %{columns: %{"0" => %{"type" => "number"}}})
      |> render_submit()

      assert has_element?(lv, "#spool-columns-error", "email can't become number")
    end

    test "a viewer only looks", %{workspace: workspace, table: table} do
      {:ok, lv, _html} = live(as_role(workspace, "viewer"), ~p"/spool/#{table.id}")

      refute has_element?(lv, "#spool-new-row")
      refute has_element?(lv, "#spool-delete-table")
      assert has_element?(lv, "#spool-export")
    end

    test "only an admin deletes it", %{
      conn: conn,
      workspace: workspace,
      scope: scope,
      table: table
    } do
      {:ok, lv, _html} = live(as_role(workspace, "editor"), ~p"/spool/#{table.id}")
      refute has_element?(lv, "#spool-delete-table")

      {:ok, lv, _html} = live(conn, ~p"/spool/#{table.id}")

      assert {:error, {:live_redirect, %{to: "/spool"}}} =
               lv |> element("#spool-delete-table") |> render_click()

      assert Spool.list_tables(scope) == []
    end
  end

  describe "export" do
    test "downloads the rows as CSV", %{conn: conn, scope: scope} do
      table = table_fixture(scope)
      {:ok, _row} = Spool.insert_row(scope, table, %{"email" => "ana@example.com", "score" => 3})

      conn = get(conn, ~p"/spool/#{table.id}/export")

      assert response_content_type(conn, :csv) =~ "text/csv"

      assert get_resp_header(conn, "content-disposition") == [
               ~s(attachment; filename="leads.csv")
             ]

      assert [header, row, ""] = String.split(response(conn, 200), "\r\n")
      assert header == "id,email,score,created_at,updated_at"
      assert row =~ ",ana@example.com,3,"
    end

    test "a table of another workspace is missing", %{scope: scope} do
      table = table_fixture(scope)

      other =
        Phoenix.ConnTest.build_conn() |> log_in_user(user_fixture() |> tap(&workspace_fixture/1))

      assert get(other, ~p"/spool/#{table.id}/export").status == 404
    end
  end
end
