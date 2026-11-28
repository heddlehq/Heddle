defmodule HeddleCore.Repo.Migrations.AddLaneToExecutions do
  use Ecto.Migration

  # Runs with the same lane run one at a time, see `HeddleCore.Executions.admit/1`.
  # `lane` holds the workspace too, like "12:jido/billing/ana". A run that found its
  # lane busy is `lane_held` until the one before it ends. `lane_position` orders the
  # runs of a lane as they were asked for: `inserted_at` has only seconds.
  def change do
    alter table(:executions) do
      add :lane, :string
      add :lane_held, :boolean, null: false, default: false
      add :lane_position, :bigserial
    end

    create index(:executions, [:lane, :lane_position], where: "lane IS NOT NULL")
  end
end
