defmodule HeddleCore.Integrations.Installed do
  @moduledoc "An integration a workspace installed."

  use Ecto.Schema
  import Ecto.Changeset

  schema "workspace_integrations" do
    field :integration, :string
    belongs_to :workspace, HeddleCore.Workspaces.Workspace

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(installed, attrs) do
    installed
    |> cast(attrs, [:workspace_id, :integration])
    |> validate_required([:workspace_id, :integration])
    |> unique_constraint([:workspace_id, :integration])
  end
end
