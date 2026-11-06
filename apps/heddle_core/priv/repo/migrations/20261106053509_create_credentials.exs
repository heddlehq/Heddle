defmodule HeddleCore.Repo.Migrations.CreateCredentials do
  use Ecto.Migration

  def change do
    create table(:credentials) do
      add :name, :string, null: false
      add :kind, :string, null: false
      add :data, :binary, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:credentials, [:name])
  end
end
