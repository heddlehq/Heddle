defmodule HeddleNodes.ConnectionsTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias HeddleNodes.Connections

  defp values, do: %{"password" => "s3cret", "id" => System.unique_integer()}

  defp idle_process do
    Agent.start_link(fn -> :connection end)
  end

  test "opens a connection once for the same values" do
    test = self()
    values = values()

    connect = fn ->
      send(test, :connected)
      idle_process()
    end

    assert Connections.with_connection(values, connect, fn _conn -> :first end) == :first
    assert Connections.with_connection(values, connect, fn _conn -> :second end) == :second

    assert_received :connected
    refute_received :connected
  end

  test "opens another connection for other values" do
    {:ok, first} = Connections.with_connection(values(), &idle_process/0, &{:ok, &1})
    {:ok, second} = Connections.with_connection(values(), &idle_process/0, &{:ok, &1})

    assert first != second
  end

  test "hands over a connection different from the process that owns it" do
    connect = fn ->
      {:ok, pid} = idle_process()
      {:ok, pid, {pid, "database"}}
    end

    assert {_pid, "database"} =
             Connections.with_connection(values(), connect, & &1)
  end

  test "answers why it couldn't connect, and tries again the next time" do
    values = values()
    assert Connections.with_connection(values, fn -> {:error, "no"} end, & &1) == {:error, "no"}

    assert {:ok, pid} = Connections.with_connection(values, &idle_process/0, &{:ok, &1})
    assert is_pid(pid)
  end

  test "opens a new connection after the driver dies" do
    values = values()
    conn = Connections.with_connection(values, &idle_process/0, & &1)
    ref = Process.monitor(conn)

    capture_log(fn ->
      Process.exit(conn, :kill)
      assert_receive {:DOWN, ^ref, :process, ^conn, :killed}
    end)

    other = Connections.with_connection(values, &idle_process/0, & &1)

    assert other != conn
  end

  test "keeps a password out of the logs when a driver raises" do
    connect = fn -> raise KeyError, key: :nope, term: [password: "s3cret"] end

    log =
      capture_log(fn ->
        assert {:error, message} = Connections.with_connection(values(), connect, & &1)
        assert message =~ "Could not connect"
        refute message =~ "s3cret"
      end)

    refute log =~ "s3cret"
  end

  describe "check/1" do
    test "returns the reason, and hides what a driver raises" do
      assert Connections.check(fn -> :ok end) == :ok

      assert Connections.check(fn -> {:error, "refused"} end) ==
               {:error, "Could not connect: refused"}

      log =
        capture_log(fn ->
          assert {:error, message} =
                   Connections.check(fn -> raise KeyError, key: :a, term: "s3cret" end)

          refute message =~ "s3cret"
        end)

      refute log =~ "s3cret"
    end

    test "survives a driver that exits while connecting" do
      assert {:error, _message} =
               Connections.check(fn ->
                 spawn_link(fn -> exit(:boom) end)
                 receive do: ({:EXIT, _pid, reason} -> {:error, inspect(reason)})
               end)
    end
  end
end
