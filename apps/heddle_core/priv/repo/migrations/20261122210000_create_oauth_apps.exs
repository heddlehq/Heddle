defmodule HeddleCore.Repo.Migrations.CreateOAuthApps do
  use Ecto.Migration

  # The app a system admin registered with a service, for the credentials of `kind`
  # that connect through OAuth 2.0. The secret is encrypted like credentials are. See
  # `HeddleCore.Credentials.OAuth`.
  def change do
    create table(:oauth_apps) do
      add :kind, :string, null: false
      add :client_id, :string, null: false
      add :client_secret, :binary, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:oauth_apps, [:kind])
  end
end
