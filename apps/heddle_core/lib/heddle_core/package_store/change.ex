defmodule HeddleCore.PackageStore.Change do
  @moduledoc """
  A change to a record that waits for its run to end, see `HeddleCore.PackageStore`.
  `version` is the one the record takes when the change is kept.
  """

  use Ecto.Schema

  schema "package_record_changes" do
    field :namespace, :string
    field :key, :string
    field :value, :map
    field :deleted, :boolean, default: false
    field :version, :integer
    belongs_to :execution, HeddleCore.Executions.Execution, type: :binary_id
    belongs_to :workspace, HeddleCore.Workspaces.Workspace

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
