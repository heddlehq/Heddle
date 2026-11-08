defmodule HeddleNodes.Nodes.Database.SqlTest do
  @moduledoc """
  Runs every SQL node on every engine. SQLite and PostgreSQL always run, and the others
  need `docker-compose.databases.yml` and `--include databases`.
  """

  use ExUnit.Case, async: false

  @moduletag timeout: 20_000

  alias HeddleNodes.Nodes.Sql

  @sqlite_path Path.join(System.tmp_dir!(), "heddle_sql_nodes_test.db")

  @postgres %{
    "engine" => "postgres",
    "host" => "localhost",
    "port" => System.get_env("HEDDLE_DB_PORT", "5432"),
    "database" => "heddle_test",
    "username" => System.get_env("POSTGRES_USER", "postgres"),
    "password" => System.get_env("POSTGRES_PASSWORD", "postgres")
  }

  @server fn engine, port, database, username, password ->
    %{
      "engine" => engine,
      "host" => "127.0.0.1",
      "port" => port,
      "database" => database,
      "username" => username,
      "password" => password
    }
  end

  @engines [
    {"sqlite", %{"engine" => "sqlite", "database" => @sqlite_path}, nil},
    {"postgres", @postgres, nil},
    {"mysql", @server.("mysql", "15401", "heddle", "root", "heddle"), :databases},
    {"mariadb", @server.("mysql", "15402", "heddle", "root", "heddle"), :databases},
    {"sqlserver", @server.("sqlserver", "15403", "master", "sa", "Heddle_12345"), :databases},
    {"oracle", @server.("oracle", "15404", "FREEPDB1", "heddle", "heddle"), :databases}
  ]

  defmodule Vault do
    # A run asks within its workspace, which these tests leave out.
    def fetch(_workspace_id, name, kind), do: fetch(name, kind)

    def fetch("db", "sql"), do: {:ok, :persistent_term.get(:heddle_sql_test_credential)}
    def fetch(name, _kind), do: {:error, "no #{name}"}
  end

  setup do
    previous = Application.get_env(:heddle_nodes, :credentials_client)
    Application.put_env(:heddle_nodes, :credentials_client, Vault)
    on_exit(fn -> Application.put_env(:heddle_nodes, :credentials_client, previous) end)
  end

  defp node_run(module, controls, context \\ %{}) do
    context = context |> Map.merge(controls) |> Map.put("credential", "db")

    case module.handler(context, nil) do
      {:ok, %{"result" => result}, "success"} -> {:ok, result}
      {:ok, %{"result" => %{"error" => message}}, "error"} -> {:error, message}
    end
  end

  defp sql!(statement, context \\ %{}) do
    {:ok, result} = node_run(Sql.RunQuery, %{"sql" => statement}, context)
    result
  end

  defp create_table(engine) do
    {id, text, number, flag} =
      case engine do
        "oracle" -> {"NUMBER(10) PRIMARY KEY", "VARCHAR2(200)", "NUMBER(10,2)", "NUMBER(1)"}
        "sqlite" -> {"INTEGER PRIMARY KEY", "TEXT", "NUMERIC", "INTEGER"}
        "sqlserver" -> {"INT PRIMARY KEY", "NVARCHAR(200)", "DECIMAL(10,2)", "BIT"}
        "postgres" -> {"INT PRIMARY KEY", "TEXT", "NUMERIC(10,2)", "BOOLEAN"}
        _mysql -> {"INT PRIMARY KEY", "VARCHAR(200)", "DECIMAL(10,2)", "BOOLEAN"}
      end

    node_run(Sql.RunQuery, %{"sql" => "DROP TABLE items"})

    sql!("CREATE TABLE items (id #{id}, name #{text}, price #{number}, active #{flag})")
  end

  for {engine, credential, tag} <- @engines do
    describe "on #{engine}" do
      @describetag engine: engine
      if tag, do: @describetag(tag)

      setup do
        :persistent_term.put(:heddle_sql_test_credential, unquote(Macro.escape(credential)))
        create_table(unquote(credential["engine"]))
      end

      test "inserts and reads rows, with values as parameters" do
        evil = "x'); DROP TABLE items; --"

        assert {:ok, %{"count" => 2}} =
                 node_run(
                   Sql.InsertRows,
                   %{
                     "table" => "items",
                     "rows" =>
                       ~s([{"id": 1, "name": {{evil}}, "price": 9.5}, {"id": 2, "name": "b", "price": 2}])
                   },
                   %{"evil" => evil}
                 )

        assert %{"rows" => [row]} =
                 sql!("SELECT id, name, price FROM items WHERE name = {{evil}}", %{"evil" => evil})

        assert %{"name" => ^evil} = row
        assert to_string(row["price"]) =~ "9.5"
      end

      test "takes text for a number, which is what a webhook sends" do
        node_run(Sql.InsertRows, %{"table" => "items", "rows" => ~s({"id": 3, "name": "c"})})

        assert %{"rows" => [%{"name" => "c"}]} =
                 sql!("SELECT name FROM items WHERE id = {{id}}", %{"id" => "3"})
      end

      test "selects with columns, where, order, limit and offset" do
        items = for id <- 1..5, do: %{"id" => id, "name" => "n#{id}"}

        node_run(Sql.InsertRows, %{"table" => "items", "rows" => "{{items}}"}, %{"items" => items})

        assert {:ok, %{"rows" => selected}} =
                 node_run(
                   Sql.SelectRows,
                   %{
                     "table" => "items",
                     "columns" => "id, name",
                     "where" => "id > {{min}}",
                     "order_by" => "id DESC",
                     "limit" => "2",
                     "offset" => "1"
                   },
                   %{"min" => 1}
                 )

        assert Enum.map(selected, & &1["name"]) == ["n4", "n3"]

        assert {:ok, %{"rows" => [_a, _b]}} =
                 node_run(Sql.SelectRows, %{"table" => "items", "limit" => "2"})
      end

      test "updates and deletes what matches, and refuses an empty where" do
        node_run(Sql.InsertRows, %{
          "table" => "items",
          "rows" => ~s([{"id": 1, "name": "a"}, {"id": 2, "name": "b"}])
        })

        assert {:ok, %{"count" => 1}} =
                 node_run(
                   Sql.UpdateRows,
                   %{
                     "table" => "items",
                     "changes" => ~s({"name": "z"}),
                     "where" => "id = {{id}}"
                   },
                   %{"id" => 2}
                 )

        assert %{"rows" => [%{"name" => "z"}]} = sql!("SELECT name FROM items WHERE id = 2")

        assert {:error, message} =
                 node_run(Sql.DeleteRows, %{"table" => "items", "where" => " "})

        assert message =~ "1 = 1"

        assert {:error, _message} =
                 node_run(Sql.UpdateRows, %{"table" => "items", "changes" => ~s({"name": "q"})})

        assert {:ok, %{"count" => 1}} =
                 node_run(Sql.DeleteRows, %{"table" => "items", "where" => "id = 1"})

        assert %{"rows" => [_only_one]} = sql!("SELECT id FROM items")
      end

      test "upserts: adds what's new and updates what exists" do
        node_run(Sql.InsertRows, %{"table" => "items", "rows" => ~s({"id": 1, "name": "old"})})

        assert {:ok, _result} =
                 node_run(Sql.UpsertRows, %{
                   "table" => "items",
                   "key_columns" => "id",
                   "rows" => ~s([{"id": 1, "name": "new"}, {"id": 2, "name": "two"}])
                 })

        assert %{"rows" => rows} = sql!("SELECT id, name FROM items ORDER BY id")
        assert Enum.map(rows, & &1["name"]) == ["new", "two"]
      end

      test "a transaction keeps everything or nothing" do
        node_run(Sql.InsertRows, %{"table" => "items", "rows" => ~s({"id": 1, "name": "a"})})

        assert {:error, _message} =
                 node_run(
                   Sql.RunTransaction,
                   %{
                     "statements" =>
                       "UPDATE items SET name = {{name}} WHERE id = 1; INSERT INTO nowhere VALUES (1);"
                   },
                   %{"name" => "changed"}
                 )

        assert %{"rows" => [%{"name" => "a"}]} = sql!("SELECT name FROM items")

        assert {:ok, %{"count" => 2}} =
                 node_run(
                   Sql.RunTransaction,
                   %{
                     "statements" =>
                       "UPDATE items SET name = {{name}} WHERE id = 1; DELETE FROM items WHERE id = 99"
                   },
                   %{"name" => "changed"}
                 )

        assert %{"rows" => [%{"name" => "changed"}]} = sql!("SELECT name FROM items")
      end

      test "lists tables and describes one" do
        assert {:ok, %{"tables" => tables}} = node_run(Sql.ListTables, %{})
        assert Enum.any?(tables, &(&1 |> String.downcase() |> String.ends_with?("items")))

        assert {:ok, %{"columns" => columns}} =
                 node_run(Sql.DescribeTable, %{"table" => "items"})

        names = Enum.map(columns, &String.downcase(&1["name"]))
        assert names == ["id", "name", "price", "active"]
        assert %{"nullable" => false} = hd(columns)
      end

      test "reports a query the database refuses" do
        assert {:error, message} = node_run(Sql.RunQuery, %{"sql" => "SELECT * FROM nowhere"})
        assert message =~ ~r/nowhere|NOWHERE|ORA-00942/
      end
    end
  end

  describe "in a flow" do
    setup do
      :persistent_term.put(:heddle_sql_test_credential, %{
        "engine" => "sqlite",
        "database" => @sqlite_path
      })

      create_table("sqlite")
    end

    defp flow(sql, connections) do
      node = fn id, type, controls ->
        %{"id" => id, "type" => type, "label" => id, "controls" => controls}
      end

      %{
        id: 1,
        nodes: [
          node.("start", "Start", %{}),
          node.("query", "SQL: Run Query", %{"credential" => "db", "sql" => sql}),
          node.("next", "Logger", %{})
        ],
        connections: [
          %{"source" => "start", "sourceOutput" => "exec", "target" => "query"}
          | Enum.map(connections, fn output ->
              %{"source" => "query", "sourceOutput" => output, "target" => "next"}
            end)
        ]
      }
    end

    test "gives the rows to the next node, with what came in as data" do
      sql!("INSERT INTO items (id, name) VALUES (1, 'a')")
      flow = flow("SELECT name FROM items WHERE name = {{name}}", ["success"])

      assert {:ok, %{"result" => %{"rows" => [%{"name" => "a"}]}}} =
               HeddleNodes.Runner.run(flow, %{"name" => "a"})

      assert {:ok, %{"result" => %{"rows" => []}}} =
               HeddleNodes.Runner.run(flow, %{"name" => "' OR '1'='1"})
    end

    test "goes through the error output when it's connected" do
      assert {:ok, %{"result" => %{"error" => message}}} =
               HeddleNodes.Runner.run(flow("SELECT * FROM nowhere", ["error"]), %{})

      assert message =~ "nowhere"
    end

    test "fails the run when nobody handles the error" do
      assert {:error, message, "query", _context} =
               HeddleNodes.Runner.run(flow("SELECT * FROM nowhere", ["success"]), %{})

      assert message =~ "nowhere"
    end
  end

  describe "a connection" do
    test "tells why it failed" do
      :persistent_term.put(
        :heddle_sql_test_credential,
        Map.put(@postgres, "password", "wrong-#{System.unique_integer()}")
      )

      assert {:error, message} = node_run(Sql.RunQuery, %{"sql" => "SELECT 1"})
      assert message =~ "Could not connect"
      refute message =~ "wrong-"
    end

    test "tells when the server is down" do
      :persistent_term.put(:heddle_sql_test_credential, %{
        "engine" => "postgres",
        "host" => "127.0.0.1",
        "port" => "1",
        "database" => "x#{System.unique_integer()}",
        "username" => "u",
        "password" => "p"
      })

      assert {:error, message} = node_run(Sql.RunQuery, %{"sql" => "SELECT 1"})
      assert message =~ "Could not connect"
    end

    test "is shared by the runs of a credential" do
      :persistent_term.put(:heddle_sql_test_credential, @postgres)
      sql!("SELECT 1")
      before = DynamicSupervisor.count_children(HeddleNodes.Connections.Supervisor).active

      for _time <- 1..5, do: sql!("SELECT 1")

      assert DynamicSupervisor.count_children(HeddleNodes.Connections.Supervisor).active == before
    end
  end

  describe "PostgreSQL types" do
    setup do
      :persistent_term.put(:heddle_sql_test_credential, @postgres)
      :ok
    end

    test "converts each value to the type of its column" do
      assert %{"rows" => [row]} =
               sql!(
                 """
                 SELECT {{a}}::int AS a, {{b}}::numeric AS b, {{c}}::boolean AS c,
                   {{d}}::date AS d, {{e}}::timestamptz AS e, {{f}}::jsonb AS f,
                   {{g}}::uuid AS g, {{h}}::text AS h, {{i}}::float8 AS i
                 """,
                 %{
                   "a" => "42",
                   "b" => "10.50",
                   "c" => "true",
                   "d" => "2026-11-07",
                   "e" => "2026-11-07T10:00:00Z",
                   "f" => %{"x" => [1, 2]},
                   "g" => "6f9619ff-8b86-d011-b42d-00c04fc964ff",
                   "h" => 12,
                   "i" => "1.5"
                 }
               )

      assert row == %{
               "a" => 42,
               "b" => "10.50",
               "c" => true,
               "d" => "2026-11-07",
               "e" => "2026-11-07T10:00:00.000000Z",
               "f" => %{"x" => [1, 2]},
               "g" => "6f9619ff-8b86-d011-b42d-00c04fc964ff",
               "h" => "12",
               "i" => 1.5
             }
    end

    test "takes a list for ANY" do
      assert %{"rows" => [%{"found" => true}]} =
               sql!("SELECT 2 = ANY({{ids}}::int[]) AS found", %{"ids" => ["1", "2"]})
    end

    test "says when a value doesn't fit" do
      assert {:error, message} =
               node_run(Sql.RunQuery, %{"sql" => "SELECT {{a}}::int"}, %{"a" => "abc"})

      assert message =~ "abc"
    end

    test "won't parse a number that would blow up in memory" do
      assert {:error, _message} =
               node_run(Sql.RunQuery, %{"sql" => "SELECT {{a}}::numeric"}, %{"a" => "1e999999999"})
    end
  end

  describe "a query that returns too much" do
    test "fails instead of filling the run" do
      :persistent_term.put(:heddle_sql_test_credential, @postgres)

      assert {:error, message} =
               node_run(Sql.RunQuery, %{"sql" => "SELECT generate_series(1, 10001)"})

      assert message =~ "LIMIT"
    end
  end
end
