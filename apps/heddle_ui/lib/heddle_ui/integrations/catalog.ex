defmodule HeddleUI.Integrations.Catalog do
  @moduledoc """
  The community integrations published in `heddlehq/integrations`, from the index its
  CI builds. Kept for ten minutes.

  When the index can't be read, what was read last stays, and it's tried again in half
  a minute: a moment of the index down, like while GitHub Pages publishes it again,
  doesn't empty the list for ten minutes. Without internet from the start there are
  none, and the official integrations work as before.
  """

  require Logger

  @key {__MODULE__, :index}
  @ttl_ms 10 * 60_000
  @retry_ms 30_000
  @default_url "https://heddlehq.github.io/integrations/index.json"

  @doc "Every integration in the index, by id."
  def all do
    case :persistent_term.get(@key, nil) do
      {at, entries, ttl} -> if now() - at < ttl, do: entries, else: fetch(entries)
      _other -> fetch(%{})
    end
  end

  @doc "The integration `id` in the index, or nil."
  def get(id), do: all()[id]

  @doc false
  # For tests: the index as if just fetched.
  def put(entries), do: store(entries, @ttl_ms)

  @doc false
  # For tests: the index as if read so long ago that the next read fetches it.
  def expire(entries), do: :persistent_term.put(@key, {now() - @ttl_ms, entries, @ttl_ms})

  @doc "Forgets the index, so the next read fetches it."
  def clear, do: :persistent_term.erase(@key)

  defp fetch(previous) do
    case download() do
      {:ok, entries} ->
        store(entries, @ttl_ms)

      {:error, reason} ->
        Logger.warning("Could not read the integrations index at #{url()}: #{reason}")
        store(previous, @retry_ms)
    end
  end

  defp download do
    options = Keyword.merge([retry: false, receive_timeout: 5_000], req_options())

    case Req.get(url(), options) do
      {:ok, %{status: 200, body: %{"integrations" => list}}} when is_list(list) ->
        entries =
          for %{"id" => id, "manifest" => manifest} = entry <- list,
              is_binary(id) and is_binary(manifest),
              into: %{},
              do: {id, entry}

        {:ok, entries}

      {:ok, %{status: 200}} ->
        {:error, "the answer isn't an index"}

      {:ok, %{status: status}} ->
        {:error, "it answered #{status}"}

      {:error, error} ->
        {:error, Exception.message(error)}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp store(entries, ttl) do
    :persistent_term.put(@key, {now(), entries, ttl})
    entries
  end

  defp url, do: Application.get_env(:heddle_ui, :integrations_index_url, @default_url)
  defp req_options, do: Application.get_env(:heddle_ui, :integrations_index_req, [])
  defp now, do: System.monotonic_time(:millisecond)
end
