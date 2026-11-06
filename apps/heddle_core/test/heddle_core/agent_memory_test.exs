defmodule HeddleCore.AgentMemoryTest do
  use HeddleCore.DataCase, async: true

  alias HeddleCore.AgentMemory

  import HeddleCore.FlowsFixtures

  test "starts empty, then keeps what it's given" do
    flow = flow_fixture()

    assert AgentMemory.load(flow.id, "ana") == []

    :ok = AgentMemory.save(flow.id, "ana", [%{role: "user", content: "Hi"}])
    :ok = AgentMemory.save(flow.id, "ana", [%{role: "user", content: "Again"}])

    assert AgentMemory.load(flow.id, "ana") == [%{role: "user", content: "Again"}]
  end

  test "keeps each key apart" do
    flow = flow_fixture()

    :ok = AgentMemory.save(flow.id, "ana", [%{role: "user", content: "Hi"}])

    assert AgentMemory.load(flow.id, "bia") == []
  end

  test "drops the oldest messages" do
    flow = flow_fixture()
    messages = for n <- 1..50, do: %{role: "user", content: "#{n}"}

    :ok = AgentMemory.save(flow.id, "ana", messages)

    loaded = AgentMemory.load(flow.id, "ana")
    assert length(loaded) == 40
    assert List.last(loaded).content == "50"
  end
end
