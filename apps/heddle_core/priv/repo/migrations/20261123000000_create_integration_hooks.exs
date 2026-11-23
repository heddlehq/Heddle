defmodule HeddleCore.Repo.Migrations.CreateIntegrationHooks do
  use Ecto.Migration

  # The address of each webhook trigger of an integration in a published flow, and what
  # the service answered when Heddle registered it, see `HeddleCore.Integrations.Hooks`.
  def change do
    create table(:integration_hooks) do
      add :flow_id, references(:flows, on_delete: :delete_all), null: false
      add :node_id, :string, null: false
      add :type, :string, null: false
      add :token, :string, null: false
      add :controls, :map, null: false, default: %{}
      add :webhook, :binary, null: false
      add :manual, :boolean, null: false, default: false
      add :error, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index(:integration_hooks, [:flow_id, :node_id])
    create unique_index(:integration_hooks, [:token])
  end
end
