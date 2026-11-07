defmodule HeddleCore.Repo.Migrations.CreateAgentMemories do
  use Ecto.Migration

  def change do
    create table(:agent_memories) do
      add :flow_id, references(:flows, on_delete: :delete_all), null: false
      add :key, :string, null: false
      add :messages, :map, null: false, default: "[]"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:agent_memories, [:flow_id, :key])
  end
end
