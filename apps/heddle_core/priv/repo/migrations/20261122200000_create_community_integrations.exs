defmodule HeddleCore.Repo.Migrations.CreateCommunityIntegrations do
  use Ecto.Migration

  # The community integrations this instance installed, with the manifest of the
  # version it runs, see `HeddleCore.Integrations`. Every workspace that installs one
  # runs that version, until a system admin updates it.
  def change do
    create table(:community_integrations) do
      add :integration, :string, null: false
      add :version, :string, null: false
      add :manifest, :text, null: false
      add :sha256, :string, null: false
      add :installed_by_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:community_integrations, [:integration])
  end
end
