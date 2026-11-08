defmodule HeddleCore.Workspaces.Workspace do
  @moduledoc """
  A place where a team keeps its flows, credentials and API keys.

  Everything a person can see or change in Heddle is in a workspace they are a member
  of, with a role. System admins act as admins in every workspace.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias HeddleCore.Workspaces.Member

  schema "workspaces" do
    field :name, :string
    field :slug, :string

    has_many :members, Member

    timestamps(type: :utc_datetime)
  end

  def changeset(workspace, attrs) do
    workspace
    |> cast(attrs, [:name, :slug])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name, :slug])
    |> validate_length(:name, min: 2, max: 60)
    |> validate_format(:slug, ~r/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/)
    |> validate_length(:slug, max: 60)
    |> unique_constraint(:slug)
  end

  @doc "Turns a name into the start of a slug: lowercase letters, digits and hyphens."
  def slugify(name) do
    name
    |> to_string()
    |> String.normalize(:nfd)
    |> String.replace(~r/[\x{0300}-\x{036f}]/u, "")
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
    |> String.slice(0, 48)
    |> String.trim("-")
    |> case do
      "" -> "workspace"
      slug -> slug
    end
  end
end
