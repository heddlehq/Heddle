defmodule HeddleCore.Integrations.PollsTest do
  use HeddleCore.DataCase, async: true

  alias HeddleCore.Integrations.Polls

  import HeddleCore.FlowsFixtures

  @now ~U[2026-11-22 10:00:00Z]

  setup do
    %{flow: flow_fixture()}
  end

  test "the first call only records what is already there", %{flow: flow} do
    assert Polls.record(flow.id, "t", [{"2", %{"n" => 2}}, {"1", %{"n" => 1}}], @now) == []
    assert %{seen_ids: ["2", "1"], polled_at: @now} = Polls.get(flow.id, "t")
  end

  test "later calls return what is new, oldest first", %{flow: flow} do
    Polls.record(flow.id, "t", [{"1", %{"n" => 1}}], @now)

    items = [{"3", %{"n" => 3}}, {"2", %{"n" => 2}}, {"1", %{"n" => 1}}]
    assert Polls.record(flow.id, "t", items, @now) == [%{"n" => 2}, %{"n" => 3}]
    assert Polls.record(flow.id, "t", items, @now) == []
    assert Polls.get(flow.id, "t").seen_ids == ["3", "2", "1"]
  end

  test "an item that left the answer and came back isn't new", %{flow: flow} do
    Polls.record(flow.id, "t", [{"2", %{}}, {"1", %{}}], @now)
    Polls.record(flow.id, "t", [{"2", %{}}], @now)

    assert Polls.record(flow.id, "t", [{"2", %{}}, {"1", %{}}], @now) == []
  end

  test "a node is due every few minutes after its last call", %{flow: flow} do
    assert Polls.due?(nil, 5, @now)

    Polls.record(flow.id, "t", [], @now)
    poll = Polls.get(flow.id, "t")

    refute Polls.due?(poll, 5, DateTime.add(@now, 4 * 60))
    assert Polls.due?(poll, 5, DateTime.add(@now, 5 * 60))
  end

  test "a failed call waits its interval and keeps what was seen", %{flow: flow} do
    Polls.failed(flow.id, "t", "Slack answered 500", @now)
    assert %{seen_ids: nil, error: "Slack answered 500"} = Polls.get(flow.id, "t")

    # Still no baseline: the first answer only records.
    assert Polls.record(flow.id, "t", [{"1", %{}}], @now) == []

    Polls.failed(flow.id, "t", "down", @now)
    assert %{seen_ids: ["1"], error: "down"} = Polls.get(flow.id, "t")
  end
end
