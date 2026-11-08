defmodule HeddleCore.Repo.Migrations.CreateForms do
  use Ecto.Migration

  # The public address of each Form Trigger. It lives outside the graph so that it
  # stays the same across publishes, and a copied node gets one of its own.
  def change do
    create table(:forms) do
      add :flow_id, references(:flows, on_delete: :delete_all), null: false
      add :node_id, :string, null: false
      add :token, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:forms, [:token])
    create unique_index(:forms, [:flow_id, :node_id])
  end
end
