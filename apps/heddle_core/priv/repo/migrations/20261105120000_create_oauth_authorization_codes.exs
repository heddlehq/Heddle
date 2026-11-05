defmodule HeddleCore.Repo.Migrations.CreateOauthAuthorizationCodes do
  use Ecto.Migration

  def change do
    create table(:oauth_authorization_codes) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :code_hash, :binary, null: false
      add :client_id, :string, null: false
      add :redirect_uri, :string, null: false
      add :code_challenge, :string, null: false
      add :scopes, {:array, :string}, null: false, default: []
      add :expires_at, :utc_datetime, null: false
      add :used_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:oauth_authorization_codes, [:user_id])
    create unique_index(:oauth_authorization_codes, [:code_hash])
  end
end
