defmodule HeddleCore.Flows do
  @moduledoc """
  The Flows context.

  A flow belongs to a workspace. What a person does goes through the functions that
  take a `HeddleCore.Accounts.Scope`, which check their role there: see
  `HeddleCore.Workspaces.Role`.
  """

  import Ecto.Query, warn: false
  alias HeddleCore.Repo

  alias HeddleCore.Accounts.Scope
  alias HeddleCore.Flows.Flow
  alias HeddleCore.Flows.Session
  alias HeddleCore.Pagination
  alias HeddleCore.Workspaces

  @doc """
  Every flow, in every workspace. For what runs flows on its own, such as the
  scheduler: a person's view goes through the functions that take a scope.
  """
  def list_flows do
    Repo.all(Flow)
  end

  @doc """
  Returns every flow whose published version has a node of `type`, in any workspace,
  with that graph: what production runs. See `HeddleCore.Flows.Versions`.
  """
  defdelegate list_flows_with_node(type),
    to: HeddleCore.Flows.Versions,
    as: :list_published_with_node

  @doc "The flows of the workspace the caller works in."
  def list_flows(%Scope{} = scope) do
    scope
    |> workspace_query()
    |> order_by([f], desc: f.inserted_at)
    |> Repo.all()
  end

  def list_flows_page(%Scope{} = scope, opts \\ %{}) do
    scope
    |> workspace_query()
    |> order_by([f], desc: f.inserted_at)
    |> Pagination.paginate(Repo, opts)
  end

  @doc """
  Gets a flow by id, for what runs flows on its own.

  Raises `Ecto.NoResultsError` if the Flow does not exist.
  """
  def get_flow!(id), do: Repo.get!(Flow, id)

  @doc """
  Gets a flow the caller may see, in any of their workspaces.

  Raises `Ecto.NoResultsError` otherwise, so a flow they can't see looks like one that
  doesn't exist.
  """
  def get_flow!(%Scope{} = scope, id) do
    get_flow(scope, id) || raise Ecto.NoResultsError, queryable: Flow
  end

  def get_flow(id), do: Repo.get(Flow, id)

  @doc """
  Gets a flow the caller may see, in any of their workspaces, or nil. While people
  edit it, its draft is what they have, which is saved a moment later: see
  `HeddleCore.Flows.Session`.
  """
  def get_flow(%Scope{} = scope, id) do
    with {:ok, id} <- cast_id(id),
         %Flow{} = flow <- Repo.get(Flow, id),
         true <- Workspaces.can?(scope, :view, flow.workspace_id) do
      live(flow)
    else
      _other -> nil
    end
  end

  # The draft as its session has it, when someone edits it.
  defp live(%Flow{} = flow) do
    case Session.peek(flow.id) do
      nil ->
        flow

      graph ->
        %{flow | nodes: graph.nodes, connections: graph.connections, comments: graph.comments}
    end
  end

  @doc """
  Joins the editing session of a flow the caller may see, for as long as the caller
  lives. Returns `{:ok, flow, %{graph: graph, seq: seq, epoch: epoch}}`, see
  `HeddleCore.Flows.Session.join/2`.
  """
  def join_session(%Scope{} = scope, id) do
    with {:ok, flow} <- fetch_for(scope, :view, id),
         {:ok, joined} <- Session.join(flow.id, scope.user && scope.user.id) do
      {:ok, flow, joined}
    end
  end

  @doc """
  Applies operations a person made on a flow they may edit, see `Heddle.Graph.Ops`.
  Returns `{:ok, seq}`, `{:error, :forbidden}` for someone who may only see it, or
  `{:error, reason}`.
  """
  def apply_operations(%Scope{} = scope, id, ops, meta \\ %{}) do
    with {:ok, flow} <- fetch_for(scope, :edit, id) do
      Session.apply_ops(flow.id, scope.user && scope.user.id, ops, meta)
    end
  end

  @doc """
  `flow` as it is saved, once its session saved what it had: for what reads the
  database, such as a run or a publish.
  """
  def saved_draft(%Flow{id: id}) do
    :ok = Session.flush(id)
    Repo.get!(Flow, id)
  end

  defp cast_id(id) when is_integer(id), do: {:ok, id}

  defp cast_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {id, ""} -> {:ok, id}
      _other -> :error
    end
  end

  defp cast_id(_id), do: :error

  @doc """
  Creates a flow from `attrs`, which must hold its `workspace_id`. For what isn't a
  person, such as seeds and tests: a person creates one with `create_flow/2`.

  A new flow isn't in production until it is published, see
  `HeddleCore.Flows.Versions.publish/3`.
  """
  def create_flow(attrs \\ %{}) do
    %Flow{}
    |> Flow.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a flow in the workspace the caller works in, as its author. Editors can.
  """
  def create_flow(%Scope{workspace: %{id: workspace_id}, user: user} = scope, attrs) do
    with :ok <- Workspaces.authorize(scope, :edit, workspace_id) do
      attrs
      |> Map.new()
      |> Map.drop([:user_id, "user_id", :workspace_id, "workspace_id"])
      |> put_owner(user && user.id, workspace_id)
      |> create_flow()
    end
  end

  def create_flow(%Scope{}, _attrs), do: {:error, :forbidden}

  defp put_owner(attrs, user_id, workspace_id) do
    if attrs |> Map.keys() |> Enum.any?(&is_binary/1) do
      Map.merge(attrs, %{"user_id" => user_id, "workspace_id" => workspace_id})
    else
      Map.merge(attrs, %{user_id: user_id, workspace_id: workspace_id})
    end
  end

  @doc """
  Updates the draft of a flow, for what isn't a person. A person changes one with
  `update_flow/3`. Production keeps running the published version.
  """
  def update_flow(%Flow{} = flow, attrs) do
    case Repo.get(Flow, flow.id) do
      nil -> {:error, :not_found}
      flow -> write(live(flow), Map.new(attrs), nil, [])
    end
  end

  # The graph goes through the session of the flow, which everyone editing it follows
  # and which is the one thing that writes it. The rest is written here.
  defp write(flow, attrs, author_id, opts) do
    changeset = Flow.changeset(flow, attrs)
    graph = Map.take(changeset.changes, [:nodes, :connections, :comments])
    rest = Map.drop(changeset.changes, [:nodes, :connections, :comments])

    if changeset.valid? do
      with {:ok, flow} <- write_graph(flow, graph, author_id, opts) do
        write_rest(flow, rest)
      end
    else
      {:error, %{changeset | action: :update}}
    end
  end

  defp write_graph(flow, graph, _author_id, _opts) when graph == %{}, do: {:ok, flow}

  defp write_graph(flow, graph, author_id, opts) do
    case Session.replace(flow.id, author_id, graph, opts) do
      {:ok, flow} ->
        {:ok, flow}

      {:error, reason} when is_binary(reason) ->
        {:error, flow |> Ecto.Changeset.change() |> Ecto.Changeset.add_error(:nodes, reason)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp write_rest(flow, rest) when rest == %{}, do: {:ok, live(flow)}

  defp write_rest(flow, rest) do
    with {:ok, flow} <- flow |> Ecto.Changeset.change(rest) |> Repo.update() do
      broadcast_flow_updated(flow)
      {:ok, live(flow)}
    end
  end

  @doc """
  Subscribes to changes of a flow, whoever makes them: the editor, the API or an agent.

  Subscribers receive `{:flow_updated, flow}`.
  """
  def subscribe_to_flow(flow_id) do
    Phoenix.PubSub.subscribe(HeddleCore.PubSub, flow_topic(flow_id))
  end

  @doc false
  def broadcast_flow_updated(%Flow{} = flow) do
    Phoenix.PubSub.broadcast(HeddleCore.PubSub, flow_topic(flow.id), {:flow_updated, flow})
  end

  defp flow_topic(flow_id), do: "flow:#{flow_id}"

  @doc """
  Changes the draft of a flow the caller may edit. Returns `{:error, :forbidden}` for
  one they can only see, and `{:error, :not_found}` for one they can't.

  The caller counts among who changed the draft, and a draft edited for a while is
  kept as a checkpoint, see `HeddleCore.Flows.Versions`, unless `checkpoint: false`:
  for a save that is kept as a version right after anyway.
  """
  def update_flow(%Scope{} = scope, %Flow{} = flow, attrs, opts \\ []) do
    with {:ok, flow} <- fetch_for(scope, :edit, flow.id) do
      attrs =
        attrs
        |> Map.new()
        |> Map.drop([
          :user_id,
          "user_id",
          :workspace_id,
          "workspace_id",
          :published_version_id,
          "published_version_id",
          :draft_contributor_ids,
          "draft_contributor_ids"
        ])

      write(flow, attrs, scope.user && scope.user.id, opts)
    end
  end

  @doc """
  Changes the settings of a flow the caller may edit, see `Flow.settings_changeset/2`.
  An error flow must be another flow of the same workspace.
  """
  def update_flow_settings(%Scope{} = scope, %Flow{} = flow, attrs) do
    with {:ok, flow} <- fetch_for(scope, :edit, flow.id) do
      attrs = Map.new(attrs, fn {key, value} -> {to_string(key), value} end)

      case attrs["error_flow_id"] do
        blank when blank in [nil, ""] ->
          save_settings(flow, %{"error_flow_id" => nil})

        id ->
          case get_flow(scope, id) do
            %Flow{workspace_id: workspace_id} = error_flow
            when workspace_id == flow.workspace_id ->
              save_settings(flow, %{"error_flow_id" => error_flow.id})

            _other ->
              {:error, :error_flow_not_found}
          end
      end
    end
  end

  defp save_settings(flow, attrs) do
    with {:ok, flow} <- flow |> Flow.settings_changeset(attrs) |> Repo.update() do
      HeddleCore.Flows.Cache.invalidate(flow.id)
      broadcast_flow_updated(flow)
      {:ok, flow}
    end
  end

  @doc "Deletes a flow, for what isn't a person."
  def delete_flow(%Flow{} = flow) do
    HeddleCore.Flows.Cache.invalidate(flow.id)
    HeddleCore.Webhooks.unregister_flow(flow)
    Repo.delete(flow)
  end

  @doc "Deletes a flow the caller may edit."
  def delete_flow(%Scope{} = scope, %Flow{} = flow) do
    with {:ok, flow} <- fetch_for(scope, :edit, flow.id) do
      delete_flow(flow)
    end
  end

  @doc """
  Gets a flow for `action`: `{:ok, flow}`, `{:error, :forbidden}` when the caller can
  see it but not do that, or `{:error, :not_found}`.
  """
  def fetch_for(%Scope{} = scope, action, id) do
    case get_flow(scope, id) do
      nil ->
        {:error, :not_found}

      flow ->
        with :ok <- Workspaces.authorize(scope, action, flow.workspace_id), do: {:ok, flow}
    end
  end

  @doc "Whether the caller may do `action` with `flow`."
  def can?(%Scope{} = scope, action, %Flow{workspace_id: workspace_id}) do
    Workspaces.can?(scope, action, workspace_id)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking flow changes.
  """
  def change_flow(%Flow{} = flow, attrs \\ %{}) do
    Flow.changeset(flow, attrs)
  end

  @doc """
  Reads a flow from the JSON of a file, to import it. See `HeddleCore.Flows.Import`.

  Returns `{:ok, %{"nodes" => ..., "connections" => ..., "comments" => ...}}` or
  `{:error, reason}`.
  """
  defdelegate import_graph(json), to: HeddleCore.Flows.Import, as: :read

  @doc """
  Makes the flow in `json` the draft of a flow the caller may edit, keeping the draft
  it had as a version. Returns `{:ok, flow}`, or `{:error, reason}` with what
  `import_graph/1` or `update_flow/3` says.
  """
  def import_into(%Scope{} = scope, %Flow{} = flow, json) do
    with {:ok, graph} <- import_graph(json),
         {:ok, flow} <- fetch_for(scope, :edit, flow.id),
         {:ok, _kept} <- HeddleCore.Flows.Versions.checkpoint(flow, scope.user && scope.user.id) do
      update_flow(scope, flow, %{
        nodes: graph["nodes"] || [],
        connections: graph["connections"] || [],
        comments: graph["comments"] || []
      })
    end
  end

  defp workspace_query(%Scope{workspace: %{id: workspace_id}} = scope) do
    if Workspaces.can?(scope, :view, workspace_id) do
      from f in Flow, where: f.workspace_id == ^workspace_id
    else
      from f in Flow, where: false
    end
  end

  defp workspace_query(%Scope{}), do: from(f in Flow, where: false)

  alias HeddleCore.Flows.ExecutionLog

  @doc """
  Creates a flow execution log.
  """
  def create_execution_log(attrs \\ %{}) do
    %ExecutionLog{}
    |> ExecutionLog.changeset(attrs)
    |> Repo.insert()
  end
end
