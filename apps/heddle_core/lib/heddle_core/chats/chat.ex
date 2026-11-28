defmodule HeddleCore.Chats.Chat do
  @moduledoc """
  The public address of a trigger that people talk to: its flow, its node and the
  token in its link. See `HeddleCore.Chats`.
  """

  use Ecto.Schema

  schema "chats" do
    field :node_id, :string
    field :token, :string
    field :flow_id, :id

    timestamps(type: :utc_datetime)
  end

  @doc "A new token, which is the only secret of a chat's link."
  def new_token, do: Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)
end
