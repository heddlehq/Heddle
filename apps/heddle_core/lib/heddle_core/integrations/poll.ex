defmodule HeddleCore.Integrations.Poll do
  @moduledoc """
  What a trigger node of an integration saw when it last called its service: the ids
  of the items, newest first, so the next call starts the flow only for new ones. No
  `seen_ids` means the service never answered yet.
  """

  use Ecto.Schema

  schema "integration_polls" do
    field :node_id, :string
    field :seen_ids, {:array, :string}
    field :polled_at, :utc_datetime
    field :error, :string
    belongs_to :flow, HeddleCore.Flows.Flow
  end
end
