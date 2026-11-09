defmodule HeddleCore.Executions.Overview do
  @moduledoc """
  How the runs of a workspace went over the last days, for the dashboard.

  Everything is counted in the database and scoped by the workspace the caller works
  in: a caller who can't see it gets an overview with nothing in it.
  """

  import Ecto.Query, warn: false

  alias HeddleCore.Accounts.Scope
  alias HeddleCore.Executions.Execution
  alias HeddleCore.Flows.Flow
  alias HeddleCore.Repo
  alias HeddleCore.Workspaces

  @default_days 14
  @recent_limit 8
  @attention_limit 5
  @flows_limit 6
  @active ~w(queued running waiting)

  @type day :: %{date: Date.t(), succeeded: integer, failed: integer, other: integer}

  @doc """
  The overview of the workspace of `scope`, over the last `:days` (14 by default),
  which end on the day of `:now`.

  Returns a map with:

    * `:days`: one entry per day, oldest first, with the runs that started on it.
    * `:totals`: the runs in those days, by outcome, with `:success_rate` as a
      percentage of the finished ones (nil when none finished) and `:avg_duration`
      in seconds.
    * `:previous`: the same totals for the days before, to compare.
    * `:active`: the runs going on now, `:queued`, `:running` and `:waiting`.
    * `:flows`: how many flows the workspace has, and how many are published.
    * `:recent`: the latest runs, with their flow.
    * `:attention`: the flows with the most failed runs in those days.
    * `:latest_flows`: the flows changed most recently, each with its last run.
  """
  def overview(%Scope{} = scope, opts \\ []) do
    days = Keyword.get(opts, :days, @default_days)
    now = Keyword.get(opts, :now, DateTime.utc_now(:second))
    today = DateTime.to_date(now)
    first_day = Date.add(today, -(days - 1))
    since = DateTime.new!(first_day, ~T[00:00:00], "Etc/UTC")
    before = DateTime.add(since, -days, :day)

    case workspace_id(scope) do
      nil ->
        empty(first_day, today)

      workspace_id ->
        runs = runs(workspace_id)

        %{
          days: per_day(runs, since, first_day, today),
          totals: totals(runs, since, nil),
          previous: totals(runs, before, since),
          active: active(runs),
          flows: flow_counts(workspace_id),
          recent: recent(runs),
          attention: attention(runs, since),
          latest_flows: latest_flows(workspace_id)
        }
    end
  end

  defp workspace_id(%Scope{workspace: %{id: id}} = scope) do
    if Workspaces.can?(scope, :view, id), do: id
  end

  defp workspace_id(_scope), do: nil

  defp runs(workspace_id) do
    from e in Execution,
      join: f in assoc(e, :flow),
      as: :flow,
      where: f.workspace_id == ^workspace_id
  end

  defp per_day(runs, since, first_day, today) do
    counts =
      from(e in runs,
        where: e.inserted_at >= ^since,
        group_by: [fragment("(? AT TIME ZONE 'UTC')::date", e.inserted_at), e.status],
        select: {fragment("(? AT TIME ZONE 'UTC')::date", e.inserted_at), e.status, count(e.id)}
      )
      |> Repo.all()
      |> Enum.group_by(&elem(&1, 0), &Tuple.delete_at(&1, 0))

    for date <- Date.range(first_day, today) do
      by_status = Map.new(Map.get(counts, date, []))

      %{
        date: date,
        succeeded: Map.get(by_status, "succeeded", 0),
        failed: Map.get(by_status, "failed", 0),
        other: by_status |> Map.drop(["succeeded", "failed"]) |> Map.values() |> Enum.sum()
      }
    end
  end

  # The runs from `from`, and before `to` when there is one.
  defp totals(runs, from, to) do
    window = from(e in runs, where: e.inserted_at >= ^from)
    window = if to, do: from(e in window, where: e.inserted_at < ^to), else: window

    by_status =
      from(e in window, group_by: e.status, select: {e.status, count(e.id)})
      |> Repo.all()
      |> Map.new()

    avg_duration =
      from(e in window,
        where: not is_nil(e.started_at) and not is_nil(e.finished_at),
        select: fragment("avg(extract(epoch from (? - ?)))::float", e.finished_at, e.started_at)
      )
      |> Repo.one()

    succeeded = Map.get(by_status, "succeeded", 0)
    failed = Map.get(by_status, "failed", 0)
    finished = succeeded + failed

    %{
      runs: by_status |> Map.values() |> Enum.sum(),
      succeeded: succeeded,
      failed: failed,
      success_rate: if(finished > 0, do: succeeded * 100 / finished),
      avg_duration: avg_duration
    }
  end

  defp active(runs) do
    by_status =
      from(e in runs,
        where: e.status in @active,
        group_by: e.status,
        select: {e.status, count(e.id)}
      )
      |> Repo.all()
      |> Map.new()

    %{
      queued: Map.get(by_status, "queued", 0),
      running: Map.get(by_status, "running", 0),
      waiting: Map.get(by_status, "waiting", 0)
    }
  end

  defp flow_counts(workspace_id) do
    from(f in Flow,
      where: f.workspace_id == ^workspace_id,
      select: %{
        total: count(f.id),
        published: filter(count(f.id), not is_nil(f.published_version_id))
      }
    )
    |> Repo.one()
  end

  defp recent(runs) do
    from(e in runs,
      order_by: [desc: e.inserted_at, desc: e.id],
      limit: @recent_limit,
      preload: [flow: ^from(f in Flow, select: struct(f, [:id, :name, :workspace_id]))]
    )
    |> Repo.all()
  end

  defp attention(runs, since) do
    from([e, flow: f] in runs,
      where: e.inserted_at >= ^since,
      group_by: [f.id, f.name],
      having: filter(count(e.id), e.status == "failed") > 0,
      order_by: [desc: filter(count(e.id), e.status == "failed"), desc: max(e.inserted_at)],
      limit: @attention_limit,
      select: %{
        id: f.id,
        name: f.name,
        runs: count(e.id),
        failed: filter(count(e.id), e.status == "failed"),
        last_failed_at: filter(max(e.inserted_at), e.status == "failed")
      }
    )
    |> Repo.all()
  end

  defp latest_flows(workspace_id) do
    flows =
      from(f in Flow,
        where: f.workspace_id == ^workspace_id,
        order_by: [desc: f.updated_at, desc: f.id],
        limit: @flows_limit,
        select: %{
          id: f.id,
          name: f.name,
          updated_at: f.updated_at,
          published?: not is_nil(f.published_version_id)
        }
      )
      |> Repo.all()

    last_runs =
      from(e in Execution,
        where: e.flow_id in ^Enum.map(flows, & &1.id),
        distinct: e.flow_id,
        order_by: [e.flow_id, desc: e.inserted_at],
        select: {e.flow_id, %{status: e.status, inserted_at: e.inserted_at}}
      )
      |> Repo.all()
      |> Map.new()

    Enum.map(flows, &Map.put(&1, :last_run, Map.get(last_runs, &1.id)))
  end

  defp empty(first_day, today) do
    zero = %{runs: 0, succeeded: 0, failed: 0, success_rate: nil, avg_duration: nil}

    %{
      days:
        for(
          date <- Date.range(first_day, today),
          do: %{date: date, succeeded: 0, failed: 0, other: 0}
        ),
      totals: zero,
      previous: zero,
      active: %{queued: 0, running: 0, waiting: 0},
      flows: %{total: 0, published: 0},
      recent: [],
      attention: [],
      latest_flows: []
    }
  end
end
