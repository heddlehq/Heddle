defmodule HeddleUI.Plugs.RateLimitTest do
  use HeddleUI.ConnCase, async: false

  alias HeddleUI.Plugs.RateLimit

  import HeddleCore.AccountsFixtures

  setup do
    ensure_ets_table()
    :ok
  end

  test "returns 429 with the standardized error payload when the limit is exceeded", %{conn: conn} do
    user = user_fixture()

    {:ok, %{api_key: api_key}} =
      HeddleCore.AccountsFixtures.create_api_key(user, %{name: "rate limit", scopes: []})

    window = div(System.system_time(:second), 60)
    bucket = {api_key.id, window}

    ensure_ets_table()
    :ets.insert(:api_rate_limit, {bucket, 100})

    on_exit(fn ->
      if :ets.info(:api_rate_limit) != :undefined do
        :ets.delete(:api_rate_limit, bucket)
      end
    end)

    conn =
      conn
      |> Plug.Conn.assign(:api_key, api_key)
      |> RateLimit.call([])

    assert conn.halted
    assert conn.status == 429

    assert Jason.decode!(conn.resp_body) == %{
             "error" => %{"code" => "rate_limited", "message" => "Too Many Requests"}
           }
  end

  test "live editing counts against a budget of its own", %{conn: conn} do
    user = user_fixture()

    {:ok, %{api_key: api_key}} =
      HeddleCore.AccountsFixtures.create_api_key(user, %{name: "live", scopes: []})

    window = div(System.system_time(:second), 60)
    api = {api_key.id, window}
    live = {{:live, api_key.id}, window}
    :ets.insert(:api_rate_limit, {api, 100})

    on_exit(fn ->
      if :ets.info(:api_rate_limit) != :undefined do
        :ets.delete(:api_rate_limit, api)
        :ets.delete(:api_rate_limit, live)
      end
    end)

    conn = Plug.Conn.assign(conn, :api_key, api_key)

    refute RateLimit.call(conn, budget: :live).halted

    :ets.insert(:api_rate_limit, {live, 1200})
    assert %{halted: true, status: 429} = RateLimit.call(conn, budget: :live)
  end

  defp ensure_ets_table do
    if :ets.info(:api_rate_limit) == :undefined do
      try do
        :ets.new(:api_rate_limit, [
          :set,
          :public,
          :named_table,
          write_concurrency: true,
          read_concurrency: true
        ])
      rescue
        ArgumentError -> :ok
      end
    end
  end
end
