defmodule HeddleCore.Integrations.Polls do
  @moduledoc """
  Keeps what each trigger node of an integration saw, see `HeddleWorker.PollWorker`.

  The first call of a node only records the items already there, so turning a flow on
  doesn't start it for everything the service holds. Each later call returns the items
  it hadn't seen.
  """

  alias HeddleCore.Integrations.Poll
  alias HeddleCore.Repo

  # Enough to tell new items apart in any one answer of a service.
  @max_seen 1000

  @doc "What the node `node_id` of the flow `flow_id` saw last, or nil."
  def get(flow_id, node_id), do: Repo.get_by(Poll, flow_id: flow_id, node_id: node_id)

  @doc "Whether the node is due, `every` minutes after its last call."
  def due?(nil, _every, _now), do: true

  def due?(%Poll{polled_at: polled_at}, every, now),
    do: DateTime.diff(now, polled_at, :second) >= every * 60 - 5

  @doc """
  Records the items of a call, `[{id, item}]` as the service gave them, and returns the
  ones the node hadn't seen, oldest first. The first call returns none.
  """
  def record(flow_id, node_id, items, now \\ DateTime.utc_now()) do
    previous = seen_ids(flow_id, node_id)
    ids = items |> Enum.map(&elem(&1, 0)) |> Enum.uniq()

    new =
      case previous do
        nil ->
          []

        seen ->
          seen = MapSet.new(seen)

          items
          |> Enum.uniq_by(&elem(&1, 0))
          |> Enum.reject(fn {id, _item} -> MapSet.member?(seen, id) end)
          |> Enum.reverse()
      end

    seen_ids = Enum.take(Enum.uniq(ids ++ (previous || [])), @max_seen)
    save(flow_id, node_id, %{seen_ids: seen_ids, polled_at: now, error: nil})

    Enum.map(new, &elem(&1, 1))
  end

  @doc "Records that a call failed, so the node waits its interval before the next."
  def failed(flow_id, node_id, message, now \\ DateTime.utc_now()) do
    save(flow_id, node_id, %{
      seen_ids: seen_ids(flow_id, node_id),
      polled_at: now,
      error: message
    })
  end

  defp seen_ids(flow_id, node_id) do
    case get(flow_id, node_id) do
      nil -> nil
      poll -> poll.seen_ids
    end
  end

  defp save(flow_id, node_id, attrs) do
    now = DateTime.truncate(attrs.polled_at, :second)

    Repo.insert!(
      struct(Poll, Map.merge(attrs, %{flow_id: flow_id, node_id: node_id, polled_at: now})),
      on_conflict: {:replace, [:seen_ids, :polled_at, :error]},
      conflict_target: [:flow_id, :node_id]
    )

    :ok
  end
end
