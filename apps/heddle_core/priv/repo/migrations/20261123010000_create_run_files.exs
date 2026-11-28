defmodule HeddleCore.Repo.Migrations.CreateRunFiles do
  use Ecto.Migration

  # The files nodes pass between them, by reference, see `HeddleCore.Files`.
  def change do
    create table(:run_files, primary_key: false) do
      add :id, :string, primary_key: true
      add :name, :string, null: false
      add :mime, :string, null: false
      add :size, :bigint, null: false
      add :content, :binary, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:run_files, [:inserted_at])
  end
end
