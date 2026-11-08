defmodule HeddleCore.Repo.Migrations.CreateWorkspaces do
  @moduledoc """
  Puts flows, credentials and API keys in workspaces, which people join with a role.

  What already exists goes to one workspace, "Default", whose members are the system
  admins: they were the only ones who could open a flow. Everyone else keeps having no
  access until an admin adds them. The credentials the AI defaults use become shared
  with every workspace, since those defaults are for the whole instance.
  """

  use Ecto.Migration

  def up do
    create table(:workspaces) do
      add :name, :string, null: false
      add :slug, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:workspaces, [:slug])

    create table(:workspace_members) do
      add :workspace_id, references(:workspaces, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :role, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:workspace_members, [:workspace_id, :user_id])
    create index(:workspace_members, [:user_id])

    alter table(:flows) do
      add :workspace_id, references(:workspaces, on_delete: :delete_all)

      modify :user_id, references(:users, on_delete: :nilify_all),
        from: references(:users, on_delete: :restrict)
    end

    alter table(:credentials) do
      add :workspace_id, references(:workspaces, on_delete: :delete_all)
    end

    alter table(:api_keys) do
      add :workspace_id, references(:workspaces, on_delete: :delete_all)
    end

    alter table(:invites) do
      add :workspace_id, references(:workspaces, on_delete: :delete_all)
      add :role, :string
    end

    alter table(:oauth_authorization_codes) do
      add :workspace_id, references(:workspaces, on_delete: :delete_all)
    end

    alter table(:users) do
      add :current_workspace_id, references(:workspaces, on_delete: :nilify_all)
    end

    flush()

    execute """
    INSERT INTO workspaces (name, slug, inserted_at, updated_at)
    SELECT 'Default', 'default', now(), now()
    WHERE EXISTS (SELECT 1 FROM users)
       OR EXISTS (SELECT 1 FROM flows)
       OR EXISTS (SELECT 1 FROM credentials)
       OR EXISTS (SELECT 1 FROM api_keys)
    """

    execute """
    INSERT INTO workspace_members (workspace_id, user_id, role, inserted_at, updated_at)
    SELECT w.id, u.id, 'admin', now(), now()
    FROM workspaces w, users u
    WHERE w.slug = 'default' AND u.is_system_admin
    """

    execute """
    UPDATE users SET current_workspace_id = (SELECT id FROM workspaces WHERE slug = 'default')
    WHERE is_system_admin
    """

    execute "UPDATE flows SET workspace_id = (SELECT id FROM workspaces WHERE slug = 'default')"

    execute "UPDATE api_keys SET workspace_id = (SELECT id FROM workspaces WHERE slug = 'default')"

    execute """
    UPDATE credentials SET workspace_id = (SELECT id FROM workspaces WHERE slug = 'default')
    WHERE name NOT IN (
      SELECT task.value ->> 'credential'
      FROM instance_settings s, jsonb_each(s.value) AS task
      WHERE s.key = 'ai_defaults'
        AND jsonb_typeof(task.value) = 'object'
        AND coalesce(task.value ->> 'credential', '') <> ''
    )
    """

    # Codes live for a minute: any left can be dropped rather than guessed.
    execute "DELETE FROM oauth_authorization_codes"

    alter table(:flows) do
      modify :workspace_id, :bigint, null: false
    end

    alter table(:api_keys) do
      modify :workspace_id, :bigint, null: false
    end

    alter table(:oauth_authorization_codes) do
      modify :workspace_id, :bigint, null: false
    end

    create index(:flows, [:workspace_id])
    create index(:api_keys, [:workspace_id])
    create index(:invites, [:workspace_id])

    drop unique_index(:credentials, [:name])
    create unique_index(:credentials, [:workspace_id, :name])

    create unique_index(:credentials, [:name],
             where: "workspace_id IS NULL",
             name: :credentials_shared_name_index
           )
  end

  def down do
    drop index(:credentials, [:name], name: :credentials_shared_name_index)
    drop unique_index(:credentials, [:workspace_id, :name])

    execute """
    DELETE FROM credentials c USING credentials other
    WHERE c.name = other.name AND c.id > other.id
    """

    create unique_index(:credentials, [:name])

    alter table(:users) do
      remove :current_workspace_id
    end

    alter table(:oauth_authorization_codes) do
      remove :workspace_id
    end

    alter table(:invites) do
      remove :workspace_id
      remove :role
    end

    alter table(:api_keys) do
      remove :workspace_id
    end

    alter table(:credentials) do
      remove :workspace_id
    end

    alter table(:flows) do
      remove :workspace_id

      modify :user_id, references(:users, on_delete: :restrict),
        from: references(:users, on_delete: :nilify_all)
    end

    drop table(:workspace_members)
    drop table(:workspaces)
  end
end
