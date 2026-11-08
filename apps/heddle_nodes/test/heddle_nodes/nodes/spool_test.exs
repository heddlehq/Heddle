defmodule HeddleNodes.Nodes.SpoolTest do
  use HeddleCore.DataCase, async: true

  import HeddleCore.AccountsFixtures

  alias HeddleNodes.Nodes.Spool.{DeleteRows, FindRows, InsertRows, UpdateRows, UpsertRows}

  setup do
    scope = user_scope_fixture()

    {:ok, _table} =
      HeddleCore.Spool.create_table(scope, %{
        "name" => "leads",
        "columns" => [%{"name" => "email"}, %{"name" => "score", "type" => "number"}]
      })

    %{context: %{"workspace_id" => scope.workspace.id, "table" => "leads"}}
  end

  test "each node is a database node of the Spool group" do
    for node <- [InsertRows, FindRows, UpdateRows, DeleteRows, UpsertRows] do
      definition = node.definition()
      assert definition.category == :database
      assert definition.group == "Spool"
      refute Enum.any?(definition.ui_fields, &(&1.type == :credential))
    end
  end

  test "insert takes the rows from a placeholder", %{context: context} do
    context =
      Map.merge(context, %{
        "form" => %{"email" => "ana@example.com", "score" => "7"},
        "rows" => "{{form}}"
      })

    assert {:ok, %{"result" => %{"count" => 1, "rows" => [row]}}, "success"} =
             InsertRows.handler(context, nil)

    assert %{"email" => "ana@example.com", "score" => 7} = row
  end

  test "find, update, upsert and delete", %{context: context} do
    insert =
      Map.put(
        context,
        "rows",
        ~s([{"email": "a@x.com", "score": 1}, {"email": "b@x.com", "score": 5}])
      )

    {:ok, _context, "success"} = InsertRows.handler(insert, nil)

    find =
      Map.merge(context, %{
        "filter" => ~s({"score": {">": "{{min}}"}}),
        "min" => 2,
        "order_by" => "email",
        "limit" => "10",
        "offset" => ""
      })

    assert {:ok, %{"result" => %{"rows" => [%{"email" => "b@x.com"}]}}, "success"} =
             FindRows.handler(find, nil)

    update =
      Map.merge(context, %{"filter" => ~s({"email": "a@x.com"}), "values" => ~s({"score": 9})})

    assert {:ok, %{"result" => %{"count" => 1}}, "success"} = UpdateRows.handler(update, nil)

    upsert = Map.merge(context, %{"key_column" => "email", "rows" => ~s({"email": "c@x.com"})})
    assert {:ok, %{"result" => %{"inserted" => 1}}, "success"} = UpsertRows.handler(upsert, nil)

    delete = Map.put(context, "filter", ~s({"score": {"empty": true}}))
    assert {:ok, %{"result" => %{"count" => 1}}, "success"} = DeleteRows.handler(delete, nil)
  end

  test "a placeholder is a value, never part of the filter", %{context: context} do
    find =
      Map.merge(context, %{
        "filter" => ~s({"email": "{{evil}}"}),
        "evil" => ~s(x", "score": {">": 0})
      })

    assert {:ok, %{"result" => %{"count" => 0}}, "success"} = FindRows.handler(find, nil)
  end

  test "problems go out the error output", %{context: context} do
    assert {:ok, %{"result" => %{"error" => message}}, "error"} =
             FindRows.handler(Map.put(context, "table", "nope"), nil)

    assert message =~ "no Spool table named nope"

    assert {:ok, %{"result" => %{"error" => "Filter: " <> _}}, "error"} =
             FindRows.handler(Map.put(context, "filter", "[1]"), nil)

    assert {:ok, %{"result" => %{"error" => "say which rows" <> _}}, "error"} =
             DeleteRows.handler(Map.put(context, "filter", ""), nil)

    assert {:ok, %{"result" => %{"error" => "There are no rows to write."}}, "error"} =
             InsertRows.handler(Map.put(context, "rows", "[]"), nil)
  end
end
