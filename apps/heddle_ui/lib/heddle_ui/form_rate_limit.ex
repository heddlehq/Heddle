defmodule HeddleUI.FormRateLimit do
  @moduledoc """
  How many times one address can send one public form in a minute, so a script can't
  flood a flow with runs. See `HeddleUI.FormController`.

  It counts in an ETS table this process owns, by minute, and forgets past minutes.
  Each node of a cluster counts on its own.
  """

  use GenServer

  @table :heddle_form_rate_limit
  @window_seconds 60
  @cleanup_every :timer.minutes(1)

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc """
  Counts one sending by `key` and says whether it is within the limit, from the
  `:form_rate_limit` config of `:heddle_ui` (10 a minute by default).
  """
  def allow?(key) do
    window = div(System.system_time(:second), @window_seconds)
    bucket = {key, window}
    count = :ets.update_counter(@table, bucket, {2, 1}, {bucket, 0})
    count <= limit()
  rescue
    # Counting never stops a person sending a form.
    ArgumentError -> true
  end

  defp limit, do: Application.get_env(:heddle_ui, :form_rate_limit, 10)

  @impl true
  def init(_opts) do
    :ets.new(@table, [:set, :public, :named_table, write_concurrency: true])
    Process.send_after(self(), :cleanup, @cleanup_every)
    {:ok, nil}
  end

  @impl true
  def handle_info(:cleanup, state) do
    window = div(System.system_time(:second), @window_seconds)
    :ets.select_delete(@table, [{{{:_, :"$1"}, :_}, [{:<, :"$1", window}], [true]}])
    Process.send_after(self(), :cleanup, @cleanup_every)
    {:noreply, state}
  end
end
