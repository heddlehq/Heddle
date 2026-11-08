defmodule HeddleUI.Plugs.RateLimit do
  @moduledoc """
  A simple sliding window rate limiter for the public API using ETS.

  Live editing (`HeddleUI.PublicAPI.V1.LiveController`) has a budget of its own,
  `rate_limit: :live`: a client sends a change or a selection as a person makes it,
  which the canvas does over its socket with no limit, so the general one would stop
  someone editing within a minute.
  """
  import Plug.Conn
  alias HeddleUI.ApiError

  @limits %{api: 100, live: 1200}
  @window_seconds 60

  def init(opts), do: opts

  def call(conn, opts) do
    if api_key = conn.assigns[:api_key] do
      check_rate_limit(conn, api_key.id, Keyword.get(opts, :budget, :api))
    else
      conn
    end
  end

  defp check_rate_limit(conn, key_id, budget) do
    now = System.system_time(:second)
    window = div(now, @window_seconds)
    bucket = {bucket_key(key_id, budget), window}

    ensure_ets_table()

    count = :ets.update_counter(:api_rate_limit, bucket, {2, 1}, {bucket, 0})

    if count > Map.fetch!(@limits, budget) do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(429, Jason.encode!(ApiError.format(:rate_limited, "Too Many Requests")))
      |> halt()
    else
      # Simple garbage collection: occasionally clear the table
      if :rand.uniform(100) == 1 do
        Task.start(fn -> cleanup_ets(window) end)
      end

      conn
    end
  end

  defp bucket_key(key_id, :api), do: key_id
  defp bucket_key(key_id, budget), do: {budget, key_id}

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

  defp cleanup_ets(current_window) do
    :ets.select_delete(:api_rate_limit, [
      {{{:"$1", :"$2"}, :_}, [{:<, :"$2", current_window}], [true]}
    ])
  end
end
