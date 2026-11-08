defmodule HeddleCore.OAuth.AuthorizationCode do
  use Ecto.Schema
  import Ecto.Changeset

  alias HeddleCore.Accounts.User

  schema "oauth_authorization_codes" do
    field :code_hash, :binary, redact: true
    field :client_id, :string
    field :redirect_uri, :string
    field :code_challenge, :string
    field :scopes, {:array, :string}, default: []
    field :expires_at, :utc_datetime
    field :used_at, :utc_datetime

    belongs_to :user, User
    belongs_to :workspace, HeddleCore.Workspaces.Workspace

    timestamps(type: :utc_datetime)
  end

  def create_changeset(code, attrs) do
    code
    |> cast(attrs, [
      :user_id,
      :workspace_id,
      :code_hash,
      :client_id,
      :redirect_uri,
      :code_challenge,
      :scopes,
      :expires_at
    ])
    |> validate_required([
      :user_id,
      :workspace_id,
      :code_hash,
      :client_id,
      :redirect_uri,
      :code_challenge,
      :expires_at
    ])
    |> foreign_key_constraint(:user_id)
    |> unique_constraint(:code_hash)
  end
end
