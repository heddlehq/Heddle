defmodule HeddleCore.Repo.Migrations.AddResponseToExecutions do
  use Ecto.Migration

  def change do
    alter table(:executions) do
      add :response, :map
    end
  end
end
