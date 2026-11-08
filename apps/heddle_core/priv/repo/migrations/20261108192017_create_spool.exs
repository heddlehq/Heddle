defmodule HeddleCore.Repo.Migrations.CreateSpool do
  use Ecto.Migration

  # Spool, the tables each workspace keeps inside Heddle. A table lists its columns,
  # and its rows hold their values by the id of each column, so renaming one rewrites
  # nothing. See `HeddleCore.Spool`.
  def change do
    create table(:spool_tables) do
      add :workspace_id, references(:workspaces, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :columns, {:array, :map}, null: false, default: []

      timestamps(type: :utc_datetime)
    end

    create unique_index(:spool_tables, [:workspace_id, :name])

    create table(:spool_rows) do
      add :table_id, references(:spool_tables, on_delete: :delete_all), null: false
      add :data, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:spool_rows, [:table_id, :id])

    execute "CREATE INDEX spool_rows_data_index ON spool_rows USING GIN (data jsonb_path_ops)",
            "DROP INDEX spool_rows_data_index"
  end
end
