defmodule HeddleCore.Repo.Migrations.AddWaitingToExecutions do
  use Ecto.Migration

  # A run a Wait paused is `waiting`, and `paused` holds what is left of it. The
  # token is the secret part of the address that resumes it.
  def up do
    alter table(:executions) do
      add :paused, :map
      add :resume_token, :string
    end

    create unique_index(:executions, [:resume_token])

    drop constraint(:executions, :executions_status_check)

    create constraint(:executions, :executions_status_check,
             check: "status in ('queued', 'running', 'waiting', 'succeeded', 'failed')"
           )
  end

  def down do
    execute "UPDATE executions SET status = 'failed' WHERE status = 'waiting'"

    drop constraint(:executions, :executions_status_check)

    create constraint(:executions, :executions_status_check,
             check: "status in ('queued', 'running', 'succeeded', 'failed')"
           )

    drop index(:executions, [:resume_token])

    alter table(:executions) do
      remove :paused
      remove :resume_token
    end
  end
end
