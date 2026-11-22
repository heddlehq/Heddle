defmodule HeddleCore.Integrations.Community do
  @moduledoc "A community integration the instance installed, at one version."

  use Ecto.Schema
  import Ecto.Changeset

  schema "community_integrations" do
    field :integration, :string
    field :version, :string
    field :manifest, :string
    field :sha256, :string
    belongs_to :installed_by, HeddleCore.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(community, attrs) do
    community
    |> cast(attrs, [:integration, :version, :manifest, :installed_by_id])
    |> validate_required([:integration, :version, :manifest])
    |> put_sha256()
    |> unique_constraint(:integration)
  end

  defp put_sha256(changeset) do
    case get_change(changeset, :manifest) do
      nil -> changeset
      manifest -> put_change(changeset, :sha256, sha256(manifest))
    end
  end

  def sha256(manifest), do: :crypto.hash(:sha256, manifest) |> Base.encode16(case: :lower)
end
