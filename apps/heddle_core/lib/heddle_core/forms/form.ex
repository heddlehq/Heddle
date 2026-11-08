defmodule HeddleCore.Forms.Form do
  @moduledoc """
  The public address of a Form Trigger: its flow, its node and the token in its link.
  See `HeddleCore.Forms`.
  """

  use Ecto.Schema

  schema "forms" do
    field :node_id, :string
    field :token, :string
    field :flow_id, :id

    timestamps(type: :utc_datetime)
  end

  @doc "A new token, which is the only secret of a form's link."
  def new_token, do: Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)
end
