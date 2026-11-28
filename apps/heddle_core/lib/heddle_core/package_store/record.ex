defmodule HeddleCore.PackageStore.Record do
  @moduledoc """
  A record an integration package keeps, see `HeddleCore.PackageStore`. `value` holds
  `%{"v" => value}`.
  """

  use Ecto.Schema

  schema "package_records" do
    field :namespace, :string
    field :key, :string
    field :value, :map
    field :version, :integer
    belongs_to :workspace, HeddleCore.Workspaces.Workspace

    timestamps(type: :utc_datetime_usec)
  end
end
