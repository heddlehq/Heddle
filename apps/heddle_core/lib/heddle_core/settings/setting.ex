defmodule HeddleCore.Settings.Setting do
  @moduledoc """
  A value that applies to the whole instance.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:key, :string, autogenerate: false}

  schema "instance_settings" do
    field :value, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  def changeset(setting, attrs) do
    setting
    |> cast(attrs, [:key, :value])
    |> validate_required([:key])
  end
end
