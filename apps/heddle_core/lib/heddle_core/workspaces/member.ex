defmodule HeddleCore.Workspaces.Member do
  @moduledoc "A person in a workspace, with a role. See `HeddleCore.Workspaces.Role`."

  use Ecto.Schema

  import Ecto.Changeset

  alias HeddleCore.Accounts.User
  alias HeddleCore.Workspaces.{Role, Workspace}

  schema "workspace_members" do
    field :role, :string

    belongs_to :workspace, Workspace
    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  def changeset(member, attrs) do
    member
    |> cast(attrs, [:role])
    |> validate_required([:role])
    |> validate_inclusion(:role, Role.all())
    |> unique_constraint([:workspace_id, :user_id])
  end
end
