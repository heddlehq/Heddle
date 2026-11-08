defmodule HeddleCore.Credentials.Credential do
  @moduledoc """
  A secret that nodes use by name. `data` holds the encrypted values, and only
  `HeddleCore.Credentials` reads it, so it stays out of ordinary queries.

  It belongs to a workspace, or to none: then it is shared with every workspace, and
  only system admins change it.
  """

  use Ecto.Schema

  import Ecto.Changeset

  schema "credentials" do
    field :name, :string
    field :kind, :string
    field :data, :binary, load_in_query: false

    belongs_to :workspace, HeddleCore.Workspaces.Workspace

    timestamps(type: :utc_datetime)
  end

  def shared?(%__MODULE__{workspace_id: workspace_id}), do: is_nil(workspace_id)

  def changeset(credential, attrs, kinds) do
    credential
    |> cast(attrs, [:name, :kind])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name, :kind])
    |> validate_length(:name, max: 100)
    |> validate_inclusion(:kind, kinds)
    |> unique_constraint(:name, name: :credentials_workspace_id_name_index)
    |> unique_constraint(:name, name: :credentials_shared_name_index)
  end
end
