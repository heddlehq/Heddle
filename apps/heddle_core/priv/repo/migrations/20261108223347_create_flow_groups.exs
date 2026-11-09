defmodule HeddleCore.Repo.Migrations.CreateFlowGroups do
  use Ecto.Migration

  # Groups that keep the flows of a workspace apart on the flows page. A flow is in
  # one group or none, and deleting a group leaves its flows without one. See
  # `HeddleCore.Flows.Groups`.
  def change do
    create table(:flow_groups) do
      add :workspace_id, references(:workspaces, on_delete: :delete_all), null: false
      add :name, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:flow_groups, [:workspace_id, "lower(name)"],
             name: :flow_groups_workspace_id_name_index
           )

    alter table(:flows) do
      add :group_id, references(:flow_groups, on_delete: :nilify_all)
    end

    create index(:flows, [:group_id])
  end
end
