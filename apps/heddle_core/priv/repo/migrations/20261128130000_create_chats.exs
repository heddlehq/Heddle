defmodule HeddleCore.Repo.Migrations.CreateChats do
  use Ecto.Migration

  def change do
    create table(:chats) do
      add :flow_id, references(:flows, on_delete: :delete_all), null: false
      add :node_id, :string, null: false
      add :token, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:chats, [:token])
    create unique_index(:chats, [:flow_id, :node_id])
  end
end
