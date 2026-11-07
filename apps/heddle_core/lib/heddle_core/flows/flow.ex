defmodule HeddleCore.Flows.Flow do
  use Ecto.Schema
  import Ecto.Changeset

  alias Heddle.Graph
  alias HeddleCore.Accounts.User
  alias HeddleCore.Flows.GraphValidator

  schema "flows" do
    field :name, :string
    field :nodes, {:array, :map}
    field :connections, {:array, :map}
    field :comments, {:array, :map}, default: []

    belongs_to :user, User
    has_many :executions, HeddleCore.Executions.Execution

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(flow, attrs) do
    flow
    |> cast(attrs, [:name, :nodes, :connections, :comments, :user_id])
    |> validate_required([:name, :user_id])
    |> assoc_constraint(:user)
    |> update_change(:nodes, &Graph.normalize_nodes/1)
    |> update_change(:connections, &Graph.normalize_connections/1)
    |> validate_graph()
    |> validate_comments()
  end

  defp validate_graph(changeset) do
    nodes = get_field(changeset, :nodes) || []
    connections = get_field(changeset, :connections) || []

    case GraphValidator.validate(nodes, connections) do
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
