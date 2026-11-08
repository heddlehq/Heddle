defmodule HeddleCore.Repo.Migrations.AddErrorFlowToFlows do
  use Ecto.Migration

  # The flow that runs when a run of this one fails. Deleting it leaves the flow
  # without one.
  def change do
    alter table(:flows) do
      add :error_flow_id, references(:flows, on_delete: :nilify_all)
    end

    create index(:flows, [:error_flow_id])
  end
end
