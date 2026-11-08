defmodule HeddleCore.Flows.Versions do
  @moduledoc """
  The versions of a flow: what it publishes and what it keeps of its draft.

  The graph of a flow is its draft, which people change as they edit. What runs in
  production (webhooks, schedules, error flows and the public API) is its published
  version, so a change reaches production only once someone publishes it. A flow that
  was never published runs only from the editor.

  Versions never change. Besides those published, a flow keeps its draft every so
  often and before something replaces it (a `"checkpoint"`), and freezes it for a
  run from the editor (a `"run"`), so a run always says what it ran. Checkpoints
  that nothing uses go after `@retention_days` days, see `prune/1`.

  Seeing versions takes `:view`, and publishing or restoring one takes `:edit`, see
  `HeddleCore.Workspaces.Role`.
  """

  import Ecto.Query, warn: false

  alias Heddle.Graph
  alias Heddle.Graph.Diff
  alias HeddleCore.Accounts.Scope
  alias HeddleCore.Accounts.User
  alias HeddleCore.Executions.Execution
  alias HeddleCore.Flows
  alias HeddleCore.Flows.{Flow, Version}
  alias HeddleCore.Repo

  @checkpoint_every_minutes 10
  @retention_days 30
  @list_limit 100

  @doc "How long a flow edits before its draft is kept on its own, in minutes."
  def checkpoint_every_minutes, do: @checkpoint_every_minutes

  ## Reading

  @doc """
  The versions of a flow the caller may see, newest first, each with what changed from
  the one before: `{:ok, [%{version: version, diff: diff, contributors: [user]}]}`.
  """
  def list_versions(%Scope{} = scope, %Flow{} = flow) do
    with {:ok, flow} <- Flows.fetch_for(scope, :view, flow.id) do
      versions =
        from(v in Version,
          where: v.flow_id == ^flow.id,
          order_by: [desc: v.number],
          limit: @list_limit + 1,
          preload: [:author, :source]
        )
        |> Repo.all()

      people = people(versions)

      entries =
        versions
        |> Enum.chunk_every(2, 1)
        |> Enum.take(@list_limit)
        |> Enum.map(fn
          [version, previous] -> entry(version, previous, people)
          [version] -> entry(version, nil, people)
        end)

      {:ok, entries}
    end
  end

  defp entry(version, previous, people) do
    %{
      version: version,
      diff: Diff.between(previous || %{nodes: [], connections: [], comments: []}, version),
      contributors: version.contributor_ids |> Enum.map(&people[&1]) |> Enum.reject(&is_nil/1)
    }
  end

  defp people(versions) do
    ids = versions |> Enum.flat_map(& &1.contributor_ids) |> Enum.uniq()
    from(u in User, where: u.id in ^ids) |> Repo.all() |> Map.new(&{&1.id, &1})
  end

  @doc "A version of a flow the caller may see, or nil."
  def get_version(%Scope{} = scope, %Flow{} = flow, id) do
    with {:ok, flow} <- Flows.fetch_for(scope, :view, flow.id),
         {:ok, id} <- cast_id(id) do
      Repo.one(
        from v in Version,
          where: v.flow_id == ^flow.id and v.id == ^id,
          preload: [:author, :source]
      )
    else
      _other -> nil
    end
  end

  @doc "The version that comes before `version`, or nil for the first one."
  def previous(%Version{} = version) do
    Repo.one(
      from v in Version,
        where: v.flow_id == ^version.flow_id and v.number < ^version.number,
        order_by: [desc: v.number],
        limit: 1
    )
  end

  @doc "The newest version of a flow, or nil."
  def latest(%Flow{id: flow_id}) do
    Repo.one(
      from v in Version, where: v.flow_id == ^flow_id, order_by: [desc: v.number], limit: 1
    )
  end

  @doc "Whether `flow` runs in production, with a published version."
  def published?(%Flow{published_version_id: id}), do: not is_nil(id)

  @doc "The version `flow` publishes, or nil."
  def published_version(%Flow{published_version_id: nil}), do: nil
  def published_version(%Flow{published_version_id: id}), do: Repo.get(Version, id)

  @doc """
  The flow as production runs it: with the graph of its published version, or nil when
  it has none.
  """
  def published_flow(%Flow{published_version_id: nil}), do: nil

  def published_flow(%Flow{published_version_id: id} = flow) do
    case Repo.get(Version, id) do
      nil -> nil
      version -> at(flow, version)
    end
  end

  @doc "`flow` with the graph of `version`."
  def at(%Flow{} = flow, %Version{} = version) do
    %{flow | nodes: version.nodes, connections: version.connections, comments: version.comments}
  end

  @doc """
  The flow as `execution` runs it: with the graph of its version. An execution from
  before there were versions runs the flow as it is.
  """
  def for_execution(%Flow{} = flow, %Execution{flow_version_id: nil}), do: flow

  def for_execution(%Flow{} = flow, %Execution{flow_version_id: id}) do
    case Repo.get(Version, id) do
      nil -> flow
      version -> at(flow, version)
    end
  end

  @doc """
  Whether the draft of `flow` differs from what it publishes. A flow that was never
  published has changes once it has anything on it.
  """
  def unpublished_changes?(%Flow{published_version_id: nil} = flow) do
    not empty_graph?(flow)
  end

  def unpublished_changes?(%Flow{published_version_id: id} = flow) do
    case Repo.get(Version, id) do
      nil -> true
      version -> not same_graph?(flow, version)
    end
  end

  @doc """
  The flows with a node of `type` in their published version, with that graph. For
  what starts runs on its own, such as the scheduler.
  """
  def list_published_with_node(type) do
    Repo.all(
      from f in Flow,
        join: v in Version,
        on: v.id == f.published_version_id,
        where: fragment("? @> ?::jsonb", v.nodes, ^[%{type: type}]),
        select: %{f | nodes: v.nodes, connections: v.connections, comments: v.comments}
    )
  end

  ## Writing

  @doc """
  Publishes the draft of a flow the caller may edit, with an optional `"note"`: it is
  what runs in production from now on. Returns `{:ok, version}`.
  """
  def publish(%Scope{} = scope, %Flow{} = flow, attrs \\ %{}) do
    with {:ok, flow} <- Flows.fetch_for(scope, :edit, flow.id) do
      publish_draft(flow, user_id(scope), attrs)
    end
  end

  @doc """
  Saves `graph` as the draft of a flow the caller may edit, and publishes it: for an
  editor whose canvas holds what isn't saved yet.

  Returns `{:ok, %{flow: flow, version: version}}`, or `{:error, stage, reason}` with
  `:save` or `:publish`.
  """
  def save_and_publish(%Scope{} = scope, %Flow{} = flow, graph, attrs \\ %{}) do
    with {:save, {:ok, flow}} <-
           {:save, Flows.update_flow(scope, flow, graph, checkpoint: false)},
         {:publish, {:ok, version}} <- {:publish, publish(scope, flow, attrs)} do
      {:ok, %{flow: Flows.get_flow!(flow.id), version: version}}
    else
      {stage, {:error, reason}} -> {:error, stage, reason}
    end
  end

  @doc """
  Publishes the draft of `flow`, for what isn't a person, such as seeds and tests. A
  person publishes with `publish/3`.
  """
  def publish_draft(%Flow{} = flow, author_id \\ nil, attrs \\ %{}) do
    flow
    |> insert(%{kind: "publish", note: note(attrs)}, author_id, from_draft: true, publish: true)
    |> after_publish()
  end

  @doc """
  Puts an older version back in production, without touching the draft: for when what
  was published broke something. Returns `{:ok, version}` with the new version.
  """
  def publish_version(%Scope{} = scope, %Flow{} = flow, version_id, attrs \\ %{}) do
    with {:ok, flow} <- Flows.fetch_for(scope, :edit, flow.id),
         %Version{} = source <- get_version(scope, flow, version_id) || {:error, :not_found} do
      flow
      |> insert(
        %{
          kind: "publish",
          note: note(attrs),
          nodes: source.nodes,
          connections: source.connections,
          comments: source.comments
        },
        user_id(scope),
        source: source,
        publish: true
      )
      |> after_publish()
    end
  end

  @doc """
  Replaces the draft of a flow the caller may edit with the graph of a version. The
  draft it had is kept first, so restoring can be undone. Returns `{:ok, flow}`.
  """
  def restore(%Scope{} = scope, %Flow{} = flow, version_id) do
    with {:ok, flow} <- Flows.fetch_for(scope, :edit, flow.id),
         %Version{} = version <- get_version(scope, flow, version_id) || {:error, :not_found},
         {:ok, _kept} <- checkpoint(flow, user_id(scope)) do
      Flows.update_flow(scope, flow, %{
        nodes: version.nodes,
        connections: version.connections,
        comments: version.comments
      })
    end
  end

  @doc """
  The version a run of the draft of `flow` takes: the newest one, if the draft hasn't
  changed since, or a new `"run"` version. Returns `{:ok, version}`.
  """
  def freeze_draft(%Flow{} = flow, author_id \\ nil) do
    case latest(flow) do
      %Version{} = version ->
        if same_graph?(flow, version),
          do: {:ok, version},
          else: insert(flow, %{kind: "run"}, author_id, from_draft: true)

      nil ->
        insert(flow, %{kind: "run"}, author_id, from_draft: true)
    end
  end

  @doc """
  Keeps the draft of `flow` as a checkpoint, unless the newest version already has it.
  Returns `{:ok, version}` with the version that has it, or `{:ok, nil}` for a flow
  with nothing on it and nothing kept yet.
  """
  def checkpoint(%Flow{} = flow, author_id \\ nil) do
    case latest(flow) do
      %Version{} = version ->
        if same_graph?(flow, version),
          do: {:ok, version},
          else: insert(flow, %{kind: "checkpoint"}, author_id, from_draft: true)

      nil ->
        if empty_graph?(flow),
          do: {:ok, nil},
          else: insert(flow, %{kind: "checkpoint"}, author_id, from_draft: true)
    end
  end

  @doc """
  Keeps the draft of `flow` when the newest version is older than
  `checkpoint_every_minutes/0`, so a long edit can be brought back to where it was.
  """
  def checkpoint_if_due(%Flow{} = flow, author_id \\ nil, now \\ DateTime.utc_now()) do
    case latest(flow) do
      %Version{inserted_at: at} = version ->
        if DateTime.diff(now, at, :minute) >= @checkpoint_every_minutes,
          do: checkpoint(flow, author_id),
          else: {:ok, version}

      nil ->
        checkpoint(flow, author_id)
    end
  end

  @doc """
  Deletes the checkpoints and run versions older than #{@retention_days} days that
  nothing needs: not published, not the newest of their flow and not what a run ran.
  Returns how many went.
  """
  def prune(now \\ DateTime.utc_now()) do
    cutoff = DateTime.add(now, -@retention_days, :day)

    {count, _} =
      Repo.delete_all(
        from v in Version,
          as: :version,
          where: v.kind in ["checkpoint", "run"] and v.inserted_at < ^cutoff,
          where:
            exists(
              from n in Version,
                where:
                  n.flow_id == parent_as(:version).flow_id and
                    n.number > parent_as(:version).number
            ),
          where:
            not exists(from f in Flow, where: f.published_version_id == parent_as(:version).id),
          where:
            not exists(from e in Execution, where: e.flow_version_id == parent_as(:version).id),
          where:
            not exists(from s in Version, where: s.source_version_id == parent_as(:version).id)
      )

    count
  end

  ## Helpers

  defp insert(%Flow{} = flow, attrs, author_id, opts) do
    Repo.transact(fn ->
      flow = Repo.one!(from f in Flow, where: f.id == ^flow.id, lock: "FOR UPDATE")

      number =
        Repo.one(from v in Version, where: v.flow_id == ^flow.id, select: max(v.number)) || 0

      graph =
        if opts[:from_draft],
          do: %{
            nodes: flow.nodes || [],
            connections: flow.connections || [],
            comments: flow.comments || []
          },
          else: %{}

      contributors = if opts[:from_draft], do: flow.draft_contributor_ids || [], else: []

      changeset =
        %Version{
          flow_id: flow.id,
          number: number + 1,
          author_id: author_id,
          source_version_id: opts[:source] && opts[:source].id
        }
        |> Version.changeset(
          graph
          |> Map.merge(attrs)
          |> Map.put(:contributor_ids, contributors)
        )

      with {:ok, version} <- Repo.insert(changeset),
           {:ok, _flow} <- after_insert(flow, version, opts) do
        {:ok, version}
      end
    end)
    |> tap(fn
      {:ok, version} -> broadcast_versions_changed(version.flow_id)
      _error -> :ok
    end)
  end

  defp after_insert(flow, version, opts) do
    changes =
      [
        opts[:from_draft] && {:draft_contributor_ids, []},
        opts[:publish] && {:published_version_id, version.id}
      ]
      |> Enum.filter(& &1)

    if changes == [] do
      {:ok, flow}
    else
      flow |> Ecto.Changeset.change(changes) |> Repo.update()
    end
  end

  defp after_publish({:ok, version}) do
    flow = Flows.get_flow!(version.flow_id)
    published = at(flow, version)

    HeddleCore.Flows.Cache.invalidate(flow.id)
    HeddleCore.Webhooks.register_flow(published)
    Flows.broadcast_flow_updated(flow)

    {:ok, Repo.preload(version, [:author, :source])}
  end

  defp after_publish(error), do: error

  @doc """
  Subscribers of a flow (see `HeddleCore.Flows.subscribe_to_flow/1`) receive
  `{:flow_versions_changed, flow_id}` whenever it keeps a new version.
  """
  def broadcast_versions_changed(flow_id) do
    Phoenix.PubSub.broadcast(
      HeddleCore.PubSub,
      "flow:#{flow_id}",
      {:flow_versions_changed, flow_id}
    )
  end

  @doc "Whether two graphs (of flows or versions) are the same."
  def same_graph?(a, b) do
    Graph.normalize_nodes(a.nodes || []) == Graph.normalize_nodes(b.nodes || []) and
      Graph.normalize_connections(a.connections || []) ==
        Graph.normalize_connections(b.connections || []) and
      (a.comments || []) == (b.comments || [])
  end

  defp empty_graph?(flow) do
    (flow.nodes || []) == [] and (flow.connections || []) == [] and (flow.comments || []) == []
  end

  defp note(attrs) do
    case attrs |> Map.new(fn {key, value} -> {to_string(key), value} end) |> Map.get("note") do
      note when is_binary(note) ->
        case String.trim(note) do
          "" -> nil
          note -> note
        end

      _other ->
        nil
    end
  end

  defp user_id(%Scope{user: %User{id: id}}), do: id
  defp user_id(_scope), do: nil

  defp cast_id(id) when is_integer(id), do: {:ok, id}

  defp cast_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {id, ""} -> {:ok, id}
      _other -> :error
    end
  end

  defp cast_id(_id), do: :error
end
