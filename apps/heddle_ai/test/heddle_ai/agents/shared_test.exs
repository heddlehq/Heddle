defmodule HeddleAI.Agents.SharedTest do
  use ExUnit.Case, async: true

  alias HeddleAI.Agents.Shared

  describe "flow_generation_rules/0" do
    test "does not ask for a Start node in front of a Webhook" do
      rules = Shared.flow_generation_rules()

      assert rules =~ "exactly ONE entry node"
      refute rules =~ "ALWAYS start the flow with a `Start` node"
    end
  end
end
