defmodule HeddleCore.Repo.Migrations.CreateFlowVersions do
  use Ecto.Migration

  # The graph of a flow is its draft. What runs in production is the version it
  # publishes, and its history is the versions it keeps: see `HeddleCore.Flows.Versions`.
  def up do
    create table(:flow_versions) do
      add :flow_id, references(:flows, on_delete: :delete_all), null: false
      add :number, :integer, null: false
      add :kind, :string, null: false
      add :nodes, :map, null: false, default: fragment("'[]'::jsonb")
      add :connections, :map, null: false, default: fragment("'[]'::jsonb")
      add :comments, :map, null: false, default: fragment("'[]'::jsonb")
      add :note, :text
      add :author_id, references(:users, on_delete: :nilify_all)
      add :contributor_ids, {:array, :bigint}, null: false, default: []
      add :source_version_id, references(:flow_versions, on_delete: :nilify_all)

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:flow_versions, [:flow_id, :number])
    create index(:flow_versions, [:author_id])
    create index(:flow_versions, [:source_version_id])

    create constraint(:flow_versions, :flow_versions_kind_check,
             check: "kind IN ('publish', 'checkpoint', 'run')"
           )

    alter table(:flows) do
      add :published_version_id, references(:flow_versions, on_delete: :nilify_all)
      add :draft_contributor_ids, {:array, :bigint}, null: false, default: []
    end

    create index(:flows, [:published_version_id])

    alter table(:executions) do
      add :flow_version_id, references(:flow_versions, on_delete: :nilify_all)
    end

    create index(:executions, [:flow_version_id])

    # Every flow that exists runs what it has now, so nothing changes in production.
    execute """
    INSERT INTO flow_versions (flow_id, number, kind, nodes, connections, comments, author_id, inserted_at)
    SELECT id, 1, 'publish', COALESCE(nodes, '[]'::jsonb), COALESCE(connections, '[]'::jsonb),
           COALESCE(comments, '[]'::jsonb), user_id, now() AT TIME ZONE 'utc'
    FROM flows
    """

    execute """
    UPDATE flows SET published_version_id = v.id
    FROM flow_versions v
    WHERE v.flow_id = flows.id
    """
  end

  def down do
    alter table(:executions) do
      remove :flow_version_id
    end

    alter table(:flows) do
      remove :published_version_id
      remove :draft_contributor_ids
    end

    drop table(:flow_versions)
  end
end
