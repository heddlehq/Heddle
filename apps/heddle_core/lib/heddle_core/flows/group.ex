defmodule HeddleCore.Flows.Group do
  @moduledoc """
  A group of flows of a workspace, see `HeddleCore.Flows.Groups`. Its workspace is set
  by the context, never taken from what a client sends.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias HeddleCore.Workspaces.Workspace

  schema "flow_groups" do
    field :name, :string

    belongs_to :workspace, Workspace

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(group, attrs) do
    group
    |> cast(attrs, [:name])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name])
    |> validate_length(:name, max: 80)
    |> unique_constraint(:name,
      name: :flow_groups_workspace_id_name_index,
      message: "is already taken by another group"
    )
  end
end
