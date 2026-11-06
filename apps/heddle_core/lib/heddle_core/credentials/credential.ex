defmodule HeddleCore.Credentials.Credential do
  @moduledoc """
  A secret that nodes use by name. `data` holds the encrypted values, and only
  `HeddleCore.Credentials` reads it, so it stays out of ordinary queries.
  """

  use Ecto.Schema

  import Ecto.Changeset

  schema "credentials" do
    field :name, :string
    field :kind, :string
    field :data, :binary, load_in_query: false

    timestamps(type: :utc_datetime)
  end

  def changeset(credential, attrs, kinds) do
    credential
    |> cast(attrs, [:name, :kind])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name, :kind])
    |> validate_length(:name, max: 100)
    |> validate_inclusion(:kind, kinds)
    |> unique_constraint(:name)
  end
end
