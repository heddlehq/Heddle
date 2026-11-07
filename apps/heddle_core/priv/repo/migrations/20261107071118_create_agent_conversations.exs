defmodule HeddleCore.Repo.Migrations.CreateAgentConversations do
  use Ecto.Migration

  def change do
    create table(:agent_conversations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :flow_id, references(:flows, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :items, :map, null: false, default: fragment("'[]'::jsonb")

      timestamps(type: :utc_datetime)
    end

    create index(:agent_conversations, [:user_id, :flow_id, :updated_at])
  end
end
