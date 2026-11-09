defmodule HeddleCore.Flows.Flow do
  use Ecto.Schema
  import Ecto.Changeset

  alias Heddle.Graph
  alias HeddleCore.Accounts.User
  alias HeddleCore.Flows.GraphValidator
  alias HeddleCore.Flows.Version
  alias HeddleCore.Workspaces.Workspace

  schema "flows" do
    field :name, :string
    field :nodes, {:array, :map}
    field :connections, {:array, :map}
    field :comments, {:array, :map}, default: []
    # Who changed the graph since the last version was kept, see `HeddleCore.Flows.Versions`.
    field :draft_contributor_ids, {:array, :integer}, default: []

    belongs_to :user, User
    # The flow that runs when a run of this one fails, see `HeddleCore.Executions`.
    belongs_to :error_flow, __MODULE__
    belongs_to :workspace, Workspace
    # Where it shows on the flows page, see `HeddleCore.Flows.Groups`.
    belongs_to :group, HeddleCore.Flows.Group
    # The graph above is the draft. What runs in production is this version, and a flow
    # without one isn't in production yet.
    belongs_to :published_version, Version
    has_many :executions, HeddleCore.Executions.Execution

    timestamps(type: :utc_datetime)
  end

  @doc """
  For a new flow. Its workspace and author are set by `HeddleCore.Flows`, never taken
  from what a client sends.
  """
  def create_changeset(flow, attrs) do
    flow
    |> cast(attrs, [:user_id, :workspace_id])
    |> validate_required([:workspace_id])
    |> assoc_constraint(:user)
    |> assoc_constraint(:workspace)
    |> changeset(attrs)
  end

  @doc false
  def changeset(flow, attrs, opts \\ []) do
    flow
    |> cast(attrs, [:name, :nodes, :connections, :comments])
    |> validate_required([:name])
    |> update_change(:nodes, &Graph.normalize_nodes/1)
    |> update_change(:connections, &Graph.normalize_connections/1)
    |> validate_graph(opts)
    |> validate_comments()
  end

  @doc """
  For the graph an editing session saves as the people in it change it, see
  `HeddleCore.Flows.Session`. It needs to be a graph, and may hold what is still being
  typed: publishing checks the rest.
  """
  def draft_changeset(flow, graph, contributor_ids) do
    flow
    |> changeset(graph, draft: true)
    |> put_change(:draft_contributor_ids, contributor_ids)
  end

  @doc """
  Changes how the flow runs, apart from its graph: for now, its error flow. The caller
  checks the error flow is one the person may use.
  """
  def settings_changeset(flow, attrs) do
    flow
    |> cast(attrs, [:error_flow_id])
    |> validate_change(:error_flow_id, fn :error_flow_id, id ->
      if id == flow.id, do: [error_flow_id: "can't be the flow itself"], else: []
    end)
    |> assoc_constraint(:error_flow)
  end

  @doc """
  Moves the flow to a group, or to none with nil. The caller checks the group is of
  the flow's workspace.
  """
  def group_changeset(flow, group_id) do
    flow
    |> change(group_id: group_id)
    |> assoc_constraint(:group)
  end

  defp validate_graph(changeset, opts) do
    nodes = get_field(changeset, :nodes) || []
    connections = get_field(changeset, :connections) || []

    case GraphValidator.validate(nodes, connections, Keyword.take(opts, [:draft])) do
      :ok -> changeset
      {:error, field, message} -> add_error(changeset, field, message)
    end
  end

  defp validate_comments(changeset) do
    case GraphValidator.validate_comments(get_field(changeset, :comments)) do
      :ok -> changeset
      {:error, field, message} -> add_error(changeset, field, message)
    end
  end
end
