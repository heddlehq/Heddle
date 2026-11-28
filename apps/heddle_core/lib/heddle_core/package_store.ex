defmodule HeddleCore.PackageStore do
  @moduledoc """
  What integration packages keep between runs: records by workspace, namespace and
  key, for `Bobbin.Host`'s store. A package names its own namespace, like `"jido"`.

  Each record has a `version`, which goes up by one at each change, so a package can
  change one only if nobody did since it read it (`version:`).

  A change made `with_run: run_id` waits until that run ends: `commit/1` keeps it when
  the run succeeds, and `discard/1` drops it when it fails. Until then that run reads
  what it changed, and no other run sees it.

  It is only reached from the nodes, which the runner pins to their run's workspace,
  so it takes the workspace as given and checks no role. Two runs creating the same
  key at once may both pass `version: 0`: a package that needs one at a time runs them
  in a lane, see `Bobbin.Host`.
  """

  import Ecto.Query

  alias HeddleCore.PackageStore.Change
  alias HeddleCore.PackageStore.Record
  alias HeddleCore.Repo

  @default_limit 100
  @max_limit 1_000

  @doc "The record `key`, as `%{key, value, version}`, or `{:error, :not_found}`."
  def get(workspace_id, namespace, key, opts \\ []) do
    case current(workspace_id, namespace, key, opts[:with_run]) do
      %{deleted: true} -> {:error, :not_found}
      nil -> {:error, :not_found}
      found -> {:ok, to_record(found)}
    end
  end

  @doc "Keeps `value` as `key`, and returns its new version. See the moduledoc."
  def put(workspace_id, namespace, key, value, opts \\ []) do
    change(workspace_id, namespace, key, opts, fn version ->
      %{value: %{"v" => value}, deleted: false, version: version}
    end)
  end

  @doc "Removes `key`. A key that isn't there is fine, unless a `version:` says otherwise."
  def delete(workspace_id, namespace, key, opts \\ []) do
    with {:ok, _version} <-
           change(workspace_id, namespace, key, opts, fn version ->
             %{value: nil, deleted: true, version: version}
           end),
         do: :ok
  end

  @doc "The records whose keys begin with `prefix`, by key."
  def list(workspace_id, namespace, prefix \\ "", opts \\ []) do
    limit = opts |> Keyword.get(:limit, @default_limit) |> min(@max_limit) |> max(1)
    pattern = like_prefix(prefix)

    kept =
      Repo.all(
        from r in Record,
          where: r.workspace_id == ^workspace_id and r.namespace == ^namespace,
          where: like(r.key, ^pattern),
          order_by: r.key,
          limit: ^limit
      )

    changed =
      case opts[:with_run] do
        nil ->
          []

        run_id ->
          Repo.all(
            from c in Change,
              where: c.execution_id == ^run_id and c.workspace_id == ^workspace_id,
              where: c.namespace == ^namespace and like(c.key, ^pattern)
          )
      end

    records =
      kept
      |> Map.new(&{&1.key, &1})
      |> Map.merge(Map.new(changed, &{&1.key, &1}))
      |> Map.values()
      |> Enum.reject(&Map.get(&1, :deleted, false))
      |> Enum.sort_by(& &1.key)
      |> Enum.take(limit)
      |> Enum.map(&to_record/1)

    {:ok, records}
  end

  @doc """
  Keeps what the run `execution_id` changed `with_run`. `HeddleCore.Executions` calls
  it as the run succeeds, in the same transaction.
  """
  def commit(execution_id) do
    changes =
      Repo.all(from c in Change, where: c.execution_id == ^execution_id, order_by: c.id)

    Enum.each(changes, fn change ->
      if change.deleted do
        Repo.delete_all(record_query(change.workspace_id, change.namespace, change.key))
      else
        now = DateTime.utc_now()

        Repo.insert!(
          %Record{
            workspace_id: change.workspace_id,
            namespace: change.namespace,
            key: change.key,
            value: change.value,
            version: change.version
          },
          on_conflict: [set: [value: change.value, version: change.version, updated_at: now]],
          conflict_target: [:workspace_id, :namespace, :key]
        )
      end
    end)

    discard(execution_id)
  end

  @doc "Drops what the run `execution_id` changed `with_run`, as it fails."
  def discard(execution_id) do
    Repo.delete_all(from c in Change, where: c.execution_id == ^execution_id)
    :ok
  end

  defp change(workspace_id, namespace, key, opts, attrs) do
    run_id = opts[:with_run]

    Repo.transaction(fn ->
      found = current(workspace_id, namespace, key, run_id, lock: true)
      version = version(found)

      case Keyword.fetch(opts, :version) do
        {:ok, expected} when expected != version ->
          Repo.rollback(:conflict)

        _any ->
          write(workspace_id, namespace, key, run_id, attrs.(version + 1))
          version + 1
      end
    end)
  end

  defp write(workspace_id, namespace, key, nil, %{deleted: true}) do
    Repo.delete_all(record_query(workspace_id, namespace, key))
  end

  defp write(workspace_id, namespace, key, nil, %{value: value, version: version}) do
    now = DateTime.utc_now()

    Repo.insert!(
      %Record{
        workspace_id: workspace_id,
        namespace: namespace,
        key: key,
        value: value,
        version: version
      },
      on_conflict: [set: [value: value, version: version, updated_at: now]],
      conflict_target: [:workspace_id, :namespace, :key]
    )
  end

  defp write(workspace_id, namespace, key, run_id, attrs) do
    Repo.insert!(
      struct(
        Change,
        Map.merge(attrs, %{
          execution_id: run_id,
          workspace_id: workspace_id,
          namespace: namespace,
          key: key
        })
      ),
      on_conflict: [set: Map.to_list(attrs)],
      conflict_target: [:execution_id, :workspace_id, :namespace, :key]
    )
  end

  # What `key` is for the run: its own change, or else what is kept.
  defp current(workspace_id, namespace, key, run_id, opts \\ []) do
    change =
      run_id &&
        Repo.one(
          from(c in Change,
            where: c.execution_id == ^run_id and c.workspace_id == ^workspace_id,
            where: c.namespace == ^namespace and c.key == ^key
          )
          |> maybe_lock(opts)
        )

    change || Repo.one(record_query(workspace_id, namespace, key) |> maybe_lock(opts))
  end

  defp maybe_lock(query, opts) do
    if opts[:lock], do: lock(query, "FOR UPDATE"), else: query
  end

  defp record_query(workspace_id, namespace, key) do
    from r in Record,
      where: r.workspace_id == ^workspace_id and r.namespace == ^namespace and r.key == ^key
  end

  defp version(nil), do: 0
  defp version(%{version: version}), do: version

  defp to_record(%{key: key, value: %{"v" => value}, version: version}),
    do: %{key: key, value: value, version: version}

  defp like_prefix(prefix) do
    String.replace(prefix, ["\\", "%", "_"], &("\\" <> &1)) <> "%"
  end
end
