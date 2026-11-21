defmodule HeddleNodes.UsageTest do
  use ExUnit.Case, async: true

  alias HeddleNodes.Usage

  @call %{input_tokens: 100, output_tokens: 20, total_cost: 0.0015}

  test "a step keeps what its calls cost, and nothing when it made none" do
    ref = Usage.enter()
    Usage.record(@call)
    Usage.record(@call)

    assert Usage.leave(ref) == %{
             "calls" => 2,
             "input_tokens" => 200,
             "output_tokens" => 40,
             "cost" => 0.003
           }

    assert Usage.leave(Usage.enter()) == nil
  end

  test "a step inside another pays only for its own calls" do
    agent = Usage.enter()
    Usage.record(@call)

    tool = Usage.enter()
    Usage.record(%{input_tokens: 5, output_tokens: 5, total_cost: 0.0001})
    assert %{"calls" => 1, "input_tokens" => 5} = Usage.leave(tool)

    Usage.record(@call)
    assert %{"calls" => 2, "input_tokens" => 200} = Usage.leave(agent)
  end

  test "a step that left its frame open doesn't take the calls of the one below" do
    outer = Usage.enter()
    _forgotten = Usage.enter()
    Usage.record(@call)

    assert %{"calls" => 1} = Usage.leave(outer)
    assert Usage.leave(make_ref()) == nil
  end

  test "keeps tokens without a price when the model's isn't known, and ignores calls outside a run" do
    assert Usage.record(@call) == :ok

    ref = Usage.enter()
    Usage.record(%{input_tokens: 3})
    Usage.record(nil)

    assert Usage.leave(ref) == %{"calls" => 2, "input_tokens" => 3, "output_tokens" => 0}
  end

  test "sums the steps of a run" do
    logs = [
      %{"node_id" => "a"},
      %{"usage" => %{"calls" => 1, "input_tokens" => 10, "output_tokens" => 2, "cost" => 0.01}},
      %{"usage" => %{"calls" => 2, "input_tokens" => 5, "output_tokens" => 1}}
    ]

    assert Usage.total(logs) == %{
             "calls" => 3,
             "input_tokens" => 15,
             "output_tokens" => 3,
             "cost" => 0.01
           }

    assert Usage.total([%{"node_id" => "a"}]) == nil
    assert Usage.total(nil) == nil
  end
end
