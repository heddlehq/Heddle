defmodule HeddleCore.SpoolTest do
  # Two tests change the limits, which are global.
  use HeddleCore.DataCase, async: false

  import HeddleCore.AccountsFixtures

  alias HeddleCore.Spool
  alias HeddleCore.Spool.Client

  @columns [
    %{"name" => "email", "type" => "text"},
    %{"name" => "total", "type" => "number"},
    %{"name" => "paid", "type" => "boolean"},
    %{"name" => "day", "type" => "date"},
    %{"name" => "meta", "type" => "json"}
  ]

  setup do
    scope = user_scope_fixture()
    {:ok, table} = Spool.create_table(scope, %{"name" => "orders", "columns" => @columns})
    %{scope: scope, table: table, workspace_id: scope.workspace.id}
  end

  defp scope_as(scope, role) do
    user = user_fixture()
    member_fixture(scope.workspace, user, role)
    user_scope_fixture(user)
  end

  describe "tables" do
    test "a table gets an id for each column", %{table: table} do
      assert [%{"id" => "c" <> _, "name" => "email", "type" => "text"} | _] = table.columns
    end

    test "lists the tables of the workspace with their rows", %{scope: scope, table: table} do
      {:ok, _row} = Spool.insert_row(scope, table, %{"email" => "a@b.c"})

      assert [%{name: "orders", row_count: 1}] = Spool.list_tables(scope)
      assert Spool.list_tables(user_scope_fixture()) == []
    end

    test "a table of another workspace looks missing", %{table: table} do
      assert Spool.get_table(user_scope_fixture(), table.id) == nil
      assert Spool.get_table(user_scope_fixture(), "nope") == nil
    end

    test "names are unique in a workspace and columns are checked", %{scope: scope} do
      assert {:error, changeset} = Spool.create_table(scope, %{"name" => "orders"})
      assert "is already the name of a table" in errors_on(changeset).name

      assert {:error, changeset} =
               Spool.create_table(scope, %{"name" => "x", "columns" => [%{"name" => "id"}]})

      assert [_message] = errors_on(changeset).columns

      assert {:error, _changeset} =
               Spool.create_table(scope, %{
                 "name" => "y",
                 "columns" => [%{"name" => "a"}, %{"name" => "A"}]
               })
    end

    test "editors create tables and only admins delete them", %{scope: scope, table: table} do
      viewer = scope_as(scope, "viewer")
      editor = scope_as(scope, "editor")

      assert {:error, :forbidden} = Spool.create_table(viewer, %{"name" => "v"})
      assert {:ok, _table} = Spool.create_table(editor, %{"name" => "e"})
      assert {:error, :forbidden} = Spool.delete_table(editor, table)
      assert {:ok, _table} = Spool.delete_table(scope, table)
    end

    test "a workspace keeps only so many tables", %{scope: scope} do
      Application.put_env(:heddle_core, :spool, max_tables: 1)
      on_exit(fn -> Application.delete_env(:heddle_core, :spool) end)

      assert {:error, {:limit, 1}} = Spool.create_table(scope, %{"name" => "more"})
    end
  end

  describe "changing columns" do
    test "renaming keeps the values", %{scope: scope, table: table} do
      {:ok, _row} = Spool.insert_row(scope, table, %{"email" => "a@b.c"})

      columns =
        Enum.map(
          table.columns,
          &if(&1["name"] == "email", do: %{&1 | "name" => "mail"}, else: &1)
        )

      assert {:ok, table} = Spool.update_table(scope, table, %{"columns" => columns})
      assert %{rows: [%{"mail" => "a@b.c"}]} = Spool.list_rows(scope, table)
    end

    test "a column left out takes its values", %{scope: scope, table: table} do
      {:ok, _row} = Spool.insert_row(scope, table, %{"email" => "a@b.c", "total" => 3})
      columns = Enum.reject(table.columns, &(&1["name"] == "email"))

      assert {:ok, table} =
               Spool.update_table(scope, table, %{"columns" => columns ++ [%{"name" => "email"}]})

      assert %{rows: [%{"email" => nil, "total" => 3}]} = Spool.list_rows(scope, table)
    end

    test "a new type converts every value, or nothing changes", %{scope: scope, table: table} do
      {:ok, _row} = Spool.insert_row(scope, table, %{"email" => "12"})

      to_number =
        Enum.map(
          table.columns,
          &if(&1["name"] == "email", do: %{&1 | "type" => "number"}, else: &1)
        )

      assert {:ok, changed} = Spool.update_table(scope, table, %{"columns" => to_number})
      assert %{rows: [%{"email" => 12}]} = Spool.list_rows(scope, changed)

      {:ok, _row} = Spool.insert_row(scope, table, %{"email" => "nope"})
      assert {:error, changeset} = Spool.update_table(scope, table, %{"columns" => to_number})
      assert [message] = errors_on(changeset).columns
      assert message =~ "email can't become number"
    end
  end

  describe "rows through the client" do
    setup %{workspace_id: workspace_id} do
      {:ok, %{"rows" => rows}} =
        Client.insert(workspace_id, "Orders", [
          %{
            "email" => "ana@example.com",
            "total" => "10.5",
            "paid" => "yes",
            "day" => "2026-01-02"
          },
          %{
            "email" => "bia@example.com",
            "total" => 30,
            "paid" => false,
            "meta" => %{"vip" => true}
          },
          %{"email" => "caio@example.com", "total" => 20}
        ])

      %{rows: rows}
    end

    test "insert converts values and returns the rows", %{rows: [ana | _]} do
      assert %{"email" => "ana@example.com", "total" => 10.5, "paid" => true, "id" => id} = ana
      assert is_integer(id)
      assert is_binary(ana["created_at"])
    end

    test "insert refuses unknown columns and wrong types, all or nothing", %{workspace_id: ws} do
      assert {:error, "the table has no column nope" <> _} =
               Client.insert(ws, "orders", [%{"nope" => 1}])

      assert {:error, message} =
               Client.insert(ws, "orders", [%{"total" => 1}, %{"total" => "many"}])

      assert message =~ "is not a number"
      assert {:ok, %{"count" => 3}} = Client.find(ws, "orders", %{})
    end

    test "find filters with every operator", %{workspace_id: ws} do
      emails = fn filter, opts ->
        {:ok, %{"rows" => rows}} = Client.find(ws, "orders", filter, opts)
        Enum.map(rows, & &1["email"])
      end

      assert emails.(%{"email" => "bia@example.com"}, []) == ["bia@example.com"]

      assert emails.(%{"total" => %{">" => 15}}, order: "total desc") == [
               "bia@example.com",
               "caio@example.com"
             ]

      assert emails.(%{"total" => %{">=" => "10.5", "<" => 30}}, order: "total") == [
               "ana@example.com",
               "caio@example.com"
             ]

      assert emails.(%{"email" => %{"contains" => "CAIO"}}, []) == ["caio@example.com"]
      assert emails.(%{"paid" => true}, []) == ["ana@example.com"]
      assert emails.(%{"paid" => %{"empty" => true}}, []) == ["caio@example.com"]
      assert emails.(%{"meta" => %{"vip" => true}}, []) == ["bia@example.com"]

      assert emails.(%{"email" => %{"!=" => "ana@example.com"}}, order: "email desc") == [
               "caio@example.com",
               "bia@example.com"
             ]

      assert emails.(%{"total" => %{"in" => [20, 30]}}, order: "email") == [
               "bia@example.com",
               "caio@example.com"
             ]

      assert emails.(%{"day" => %{">" => "2026-01-01"}}, []) == ["ana@example.com"]
      assert emails.(%{}, order: "email desc", limit: 1, offset: 1) == ["bia@example.com"]
    end

    test "find says what is wrong with a filter", %{workspace_id: ws} do
      assert {:error, "the table has no column nope"} = Client.find(ws, "orders", %{"nope" => 1})
      assert {:error, message} = Client.find(ws, "orders", %{"total" => %{">" => "x"}})
      assert message =~ "is not a number"
      assert {:error, message} = Client.find(ws, "orders", %{"paid" => %{">" => true}})
      assert message =~ "doesn't compare"
      assert {:error, _message} = Client.find(ws, "orders", "status = 1")
      assert {:error, _message} = Client.find(ws, "orders", %{}, order: "nope")
    end

    test "a value can't change the query", %{workspace_id: ws} do
      assert {:ok, %{"count" => 0}} =
               Client.find(ws, "orders", %{
                 "email" => "' OR 1=1 --",
                 "total" => %{"contains" => "%"}
               })
    end

    test "update changes and clears columns of the rows found", %{
      workspace_id: ws,
      rows: [ana | _]
    } do
      assert {:ok, %{"count" => 1, "ids" => [id]}} =
               Client.update(ws, "orders", %{"id" => "#{ana["id"]}"}, %{
                 "total" => 99,
                 "paid" => nil
               })

      assert id == ana["id"]
      assert {:ok, %{"rows" => [row]}} = Client.find(ws, "orders", %{"id" => id})
      assert %{"total" => 99, "paid" => nil, "email" => "ana@example.com"} = row
    end

    test "update and delete need a filter", %{workspace_id: ws} do
      assert {:error, "say which rows" <> _} = Client.update(ws, "orders", %{}, %{"total" => 1})
      assert {:error, "say which rows" <> _} = Client.delete(ws, "orders", %{})
    end

    test "delete removes the rows found", %{workspace_id: ws} do
      assert {:ok, %{"count" => 2}} = Client.delete(ws, "orders", %{"total" => %{"<=" => 20}})
      assert {:ok, %{"count" => 1}} = Client.find(ws, "orders", %{})
    end

    test "upsert changes the row with the key, and adds the rest", %{workspace_id: ws} do
      assert {:ok, %{"inserted" => 1, "updated" => 1, "rows" => [ana, dani]}} =
               Client.upsert(ws, "orders", "email", [
                 %{"email" => "ana@example.com", "total" => 1},
                 %{"email" => "dani@example.com", "total" => 2}
               ])

      assert ana["total"] == 1 and ana["paid"] == true
      assert dani["total"] == 2
      assert {:ok, %{"count" => 4}} = Client.find(ws, "orders", %{})
      assert {:error, _message} = Client.upsert(ws, "orders", "email", [%{"total" => 1}])
      assert {:error, _message} = Client.upsert(ws, "orders", "nope", [%{"total" => 1}])
    end

    test "a run reaches only its own workspace" do
      other = user_scope_fixture()

      assert {:error, "this workspace has no Spool table named orders"} =
               Client.find(other.workspace.id, "orders", %{})

      assert {:error, _message} = Client.find(nil, "orders", %{})
    end

    test "a table keeps only so many rows and so big", %{workspace_id: ws} do
      Application.put_env(:heddle_core, :spool, max_rows: 3, max_row_bytes: 100)
      on_exit(fn -> Application.delete_env(:heddle_core, :spool) end)

      assert {:error, "the table orders can't hold more than 3 rows"} =
               Client.insert(ws, "orders", [%{"total" => 1}])

      assert {:ok, _deleted} = Client.delete(ws, "orders", %{"total" => 20})

      assert {:error, "a row can't take more than" <> _} =
               Client.insert(ws, "orders", [%{"email" => String.duplicate("a", 200)}])
    end
  end

  describe "rows for people" do
    test "editors change rows, viewers only see them", %{scope: scope, table: table} do
      viewer = scope_as(scope, "viewer")

      assert {:error, :forbidden} = Spool.insert_row(viewer, table, %{"email" => "a"})
      assert {:ok, row} = Spool.insert_row(scope, table, %{"email" => "a", "total" => "1"})

      assert {:ok, %{"email" => "b", "total" => nil}} =
               Spool.update_row(scope, table, row["id"], %{"email" => "b", "total" => ""})

      assert %{rows: [_row], total: 1} = Spool.list_rows(viewer, table)
      assert {:error, :forbidden} = Spool.delete_row(viewer, table, row["id"])
      assert :ok = Spool.delete_row(scope, table, "#{row["id"]}")
      assert {:error, _message} = Spool.delete_row(scope, table, row["id"])
    end

    test "searches every value and pages newest first", %{scope: scope, table: table} do
      for n <- 1..3, do: Spool.insert_row(scope, table, %{"email" => "user#{n}@x.com"})

      assert %{rows: [%{"email" => "user2@x.com"}], total: 1} =
               Spool.list_rows(scope, table, search: "USER2")

      assert %{rows: [%{"email" => "user3@x.com"}], total: 3} =
               Spool.list_rows(scope, table, per_page: 1)
    end

    test "exports CSV, with formulas made harmless", %{scope: scope, table: table} do
      {:ok, _row} =
        Spool.insert_row(scope, table, %{
          "email" => "=cmd",
          "total" => -2,
          "meta" => %{"a" => "b,c"}
        })

      {:ok, lines} = Spool.export_csv(scope, table, [], fn line, acc -> {:cont, [line | acc]} end)
      [header, row] = lines |> Enum.reverse() |> Enum.map(&IO.iodata_to_binary/1)

      assert header == "id,email,total,paid,day,meta,created_at,updated_at\r\n"
      assert row =~ ~s(,'=cmd,-2,,,"{""a"":""b,c""}",)
    end
  end
end
