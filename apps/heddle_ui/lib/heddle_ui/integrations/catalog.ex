defmodule HeddleUI.Integrations.Catalog do
  @moduledoc """
  The community integrations published in `heddlehq/integrations`, from the index its
  CI builds. Kept for ten minutes. Without internet, or with the index down, there
  are none, and the official integrations work as before.
  """

  @key {__MODULE__, :index}
  @ttl_ms 10 * 60_000
  @default_url "https://heddlehq.github.io/integrations/index.json"

  @doc "Every integration in the index, by id."
  def all do
    case :persistent_term.get(@key, nil) do
      {at, entries} ->
        if now() - at < @ttl_ms, do: entries, else: fetch()

      nil ->
        fetch()
    end
  end

  @doc "The integration `id` in the index, or nil."
  def get(id), do: all()[id]

  @doc false
  # For tests: the index as if just fetched.
  def put(entries), do: :persistent_term.put(@key, {now(), entries})

  @doc "Forgets the index, so the next read fetches it."
  def clear, do: :persistent_term.erase(@key)

  defp fetch do
    options = Keyword.merge([retry: false, receive_timeout: 5_000], req_options())

    entries =
      case Req.get(url(), options) do
        {:ok, %{status: 200, body: %{"integrations" => list}}} when is_list(list) ->
          for %{"id" => id, "manifest" => manifest} = entry <- list,
              is_binary(id) and is_binary(manifest),
              into: %{},
              do: {id, entry}

        _other ->
          %{}
      end

    :persistent_term.put(@key, {now(), entries})
    entries
  rescue
    _error -> %{}
  end

  defp url, do: Application.get_env(:heddle_ui, :integrations_index_url, @default_url)
  defp req_options, do: Application.get_env(:heddle_ui, :integrations_index_req, [])
  defp now, do: System.monotonic_time(:millisecond)
end
