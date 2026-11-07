defmodule HeddleCore.AgentConversations do
  @moduledoc """
  The conversations a person had with the agent about a flow.
  """

  import Ecto.Query, warn: false

  alias HeddleCore.Accounts.Scope
  alias HeddleCore.AgentConversations.AgentConversation
  alias HeddleCore.Repo

  @listed 30

  @doc "Returns the latest conversations about a flow, without their items."
  def list_conversations(%Scope{user: %{id: user_id}}, flow_id) do
    Repo.all(
      from c in AgentConversation,
        where: c.user_id == ^user_id and c.flow_id == ^flow_id,
        order_by: [desc: c.updated_at, desc: c.inserted_at],
        limit: @listed,
        select: %{id: c.id, title: c.title, updated_at: c.updated_at}
    )
  end

  def get_conversation(%Scope{user: %{id: user_id}}, flow_id, id) do
    with {:ok, id} <- Ecto.UUID.cast(id) do
      Repo.get_by(AgentConversation, id: id, user_id: user_id, flow_id: flow_id)
    else
      :error -> nil
    end
  end

  @doc "Saves a conversation: a new one when `id` is nil. Returns the conversation."
  def save_conversation(%Scope{user: user}, flow_id, nil, attrs) do
    %AgentConversation{user_id: user.id, flow_id: to_integer(flow_id)}
    |> AgentConversation.changeset(attrs)
    |> Repo.insert()
  end

  def save_conversation(%Scope{} = scope, flow_id, id, attrs) do
    case get_conversation(scope, flow_id, id) do
      nil -> save_conversation(scope, flow_id, nil, attrs)
      conversation -> conversation |> AgentConversation.changeset(attrs) |> Repo.update()
    end
  end

  defp to_integer(id) when is_integer(id), do: id
  defp to_integer(id) when is_binary(id), do: String.to_integer(id)
end
