defmodule HeddleCore.Repo.Migrations.CreatePackageRecords do
  use Ecto.Migration

  # What an integration package keeps between runs, by workspace, see
  # `HeddleCore.PackageStore`. `value` holds `%{"v" => value}`, so any JSON value fits.
  # A change a run made `with_run` waits in `package_record_changes` until the run
  # ends: it is kept if the run succeeds, and dropped with it otherwise.
  def change do
    create table(:package_records) do
      add :workspace_id, references(:workspaces, on_delete: :delete_all), null: false
      add :namespace, :string, null: false
      add :key, :string, null: false
      add :value, :map, null: false
      add :version, :integer, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:package_records, [:workspace_id, :namespace, :key])

    create table(:package_record_changes) do
      add :execution_id, references(:executions, type: :binary_id, on_delete: :delete_all),
        null: false

      add :workspace_id, references(:workspaces, on_delete: :delete_all), null: false
      add :namespace, :string, null: false
      add :key, :string, null: false
      add :value, :map
      add :deleted, :boolean, null: false, default: false
      add :version, :integer, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:package_record_changes, [:execution_id, :workspace_id, :namespace, :key])
  end
end
