defmodule HeddleCore.Spool.Row do
  @moduledoc """
  A row of a Spool table: its values by the id of each column. See
  `HeddleCore.Spool.Column`.
  """

  use Ecto.Schema

  schema "spool_rows" do
    field :data, :map, default: %{}
    field :table_id, :id

    timestamps(type: :utc_datetime_usec)
  end
end
