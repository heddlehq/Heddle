defmodule HeddleCore.Repo.Migrations.CreateIntegrationPolls do
  use Ecto.Migration

  # What each trigger node of an integration saw when it last called its service, see
  # `HeddleCore.Integrations.Polls`. No `seen_ids` yet means no answer yet.
  def change do
    create table(:integration_polls) do
      add :flow_id, references(:flows, on_delete: :delete_all), null: false
      add :node_id, :string, null: false
      add :seen_ids, {:array, :string}
      add :polled_at, :utc_datetime, null: false
      add :error, :text
    end

    create unique_index(:integration_polls, [:flow_id, :node_id])
  end
end
