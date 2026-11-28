defmodule HeddleUI.Integrations.CatalogTest do
  # The index is global: one test at a time.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias HeddleUI.Integrations.Catalog

  @entry %{"id" => "asana", "name" => "Asana", "manifest" => "id: asana\n"}

  setup do
    Application.put_env(:heddle_ui, :integrations_index_req, plug: {Req.Test, Catalog})

    on_exit(fn ->
      Application.delete_env(:heddle_ui, :integrations_index_req)
      Catalog.clear()
    end)

    Catalog.clear()
    :ok
  end

  test "reads the index and keeps it" do
    Req.Test.stub(Catalog, fn conn ->
      Req.Test.json(conn, %{"format" => 1, "integrations" => [@entry]})
    end)

    assert Catalog.all() == %{"asana" => @entry}

    Req.Test.stub(Catalog, fn _conn -> flunk("read the index again while it was fresh") end)
    assert Catalog.get("asana") == @entry
  end

  test "keeps what it read last when the index is down" do
    Catalog.expire(%{"asana" => @entry})

    Req.Test.stub(Catalog, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("text/html")
      |> Plug.Conn.send_resp(404, "Not Found")
    end)

    log = capture_log(fn -> assert Catalog.all() == %{"asana" => @entry} end)
    assert log =~ "it answered 404"
  end

  test "tries again soon after a failure, instead of in ten minutes" do
    Req.Test.stub(Catalog, &Req.Test.transport_error(&1, :econnrefused))
    capture_log(fn -> assert Catalog.all() == %{} end)

    # Still within the half minute: no new request.
    Req.Test.stub(Catalog, fn _conn -> flunk("tried again at once") end)
    assert Catalog.all() == %{}
  end

  test "an index from the old cache shape is read again" do
    :persistent_term.put({Catalog, :index}, {System.monotonic_time(:millisecond), %{}})

    Req.Test.stub(Catalog, fn conn ->
      Req.Test.json(conn, %{"format" => 1, "integrations" => [@entry]})
    end)

    assert Catalog.all() == %{"asana" => @entry}
  end
end
