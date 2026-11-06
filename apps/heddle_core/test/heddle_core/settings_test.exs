defmodule HeddleCore.SettingsTest do
  use HeddleCore.DataCase, async: true

  alias HeddleCore.Settings

  describe "claude agent" do
    test "starts disabled" do
      refute Settings.claude_agent_enabled?()
    end

    test "can be turned on and off" do
      assert {:ok, _setting} = Settings.set_claude_agent_enabled(true)
      assert Settings.claude_agent_enabled?()

      assert {:ok, _setting} = Settings.set_claude_agent_enabled(false)
      refute Settings.claude_agent_enabled?()
    end
  end
end
