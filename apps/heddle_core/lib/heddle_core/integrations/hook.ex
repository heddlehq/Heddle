defmodule HeddleCore.Integrations.Hook do
  @moduledoc """
  The address of a webhook trigger in a published flow: `token` names it in
  `/hooks/:token`, `controls` are the node's when it was registered, and `webhook`
  holds, encrypted, what the service needs to know it (`url`, `secret`, the `id` it
  gave). `manual` means the person pastes the address in the service by hand.
  See `HeddleCore.Integrations.Hooks`.
  """

  use Ecto.Schema

  schema "integration_hooks" do
    field :node_id, :string
    field :type, :string
    field :token, :string
    field :controls, :map, default: %{}
    field :webhook, :binary
    field :manual, :boolean, default: false
    field :error, :string
    belongs_to :flow, HeddleCore.Flows.Flow

    timestamps(type: :utc_datetime)
  end
end
