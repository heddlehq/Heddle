defmodule HeddleCore.AgentConversations.AgentConversation do
  use Ecto.Schema
  import Ecto.Changeset

  alias HeddleCore.Accounts.User
  alias HeddleCore.Flows.Flow

  @primary_key {:id, :binary_id, autogenerate: true}
  @title_length 80

  schema "agent_conversations" do
    field :title, :string
    field :items, {:array, :map}, default: []

    belongs_to :user, User
    belongs_to :flow, Flow

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:title, :items])
    |> update_change(:title, &String.slice(&1, 0, @title_length))
    |> validate_required([:title])
    |> assoc_constraint(:user)
    |> assoc_constraint(:flow)
  end
end
