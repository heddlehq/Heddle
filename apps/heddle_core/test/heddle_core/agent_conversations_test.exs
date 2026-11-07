defmodule HeddleCore.AgentConversationsTest do
  use HeddleCore.DataCase, async: true

  import HeddleCore.AccountsFixtures
  import HeddleCore.FlowsFixtures

  alias HeddleCore.Accounts.Scope
  alias HeddleCore.AgentConversations

  setup do
    user = user_fixture()
    %{scope: Scope.for_user(user), flow: flow_fixture(%{user: user})}
  end

  defp save(scope, flow, id \\ nil, title \\ "hi") do
    {:ok, conversation} =
      AgentConversations.save_conversation(scope, flow.id, id, %{
        title: title,
        items: [%{"role" => "user", "text" => title}]
      })

    conversation
  end

  test "keeps a conversation and brings it back", %{scope: scope, flow: flow} do
    conversation = save(scope, flow)

    assert %{items: [%{"text" => "hi"}]} =
             AgentConversations.get_conversation(scope, flow.id, conversation.id)
  end

  test "updates the same conversation when it has an id", %{scope: scope, flow: flow} do
    conversation = save(scope, flow)
    save(scope, flow, conversation.id, "changed")

    assert [%{title: "changed"}] = AgentConversations.list_conversations(scope, flow.id)
  end

  test "shortens a long title", %{scope: scope, flow: flow} do
    conversation = save(scope, flow, nil, String.duplicate("a", 300))

    assert String.length(conversation.title) == 80
  end

  test "keeps them per person", %{scope: scope, flow: flow} do
    conversation = save(scope, flow)
    other = Scope.for_user(user_fixture())

    assert AgentConversations.list_conversations(other, flow.id) == []
    assert AgentConversations.get_conversation(other, flow.id, conversation.id) == nil
  end

  test "ignores an id that isn't one", %{scope: scope, flow: flow} do
    assert AgentConversations.get_conversation(scope, flow.id, "nope") == nil
  end
end
