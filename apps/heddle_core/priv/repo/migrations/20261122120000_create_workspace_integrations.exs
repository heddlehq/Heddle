defmodule HeddleCore.Repo.Migrations.CreateWorkspaceIntegrations do
  use Ecto.Migration

  # The integrations each workspace installed, see `HeddleCore.Integrations`. The ones
  # its flows already use count as installed without a row, so existing workspaces
  # need none.
  def change do
    create table(:workspace_integrations) do
      add :workspace_id, references(:workspaces, on_delete: :delete_all), null: false
      add :integration, :string, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:workspace_integrations, [:workspace_id, :integration])
  end
end
