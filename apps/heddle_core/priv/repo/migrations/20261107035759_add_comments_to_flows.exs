defmodule HeddleCore.Repo.Migrations.AddCommentsToFlows do
  use Ecto.Migration

  def change do
    alter table(:flows) do
      add :comments, :map, null: false, default: fragment("'[]'::jsonb")
    end
  end
end
