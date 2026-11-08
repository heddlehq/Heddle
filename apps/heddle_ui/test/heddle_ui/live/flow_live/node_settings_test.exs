defmodule HeddleUI.FlowLive.NodeSettingsTest do
  use ExUnit.Case, async: true

  alias HeddleUI.FlowLive.NodeSettings

  describe "from_params/1" do
    test "keeps only what isn't the default" do
      params = %{
        "retries" => "3",
        "retry_delay" => "1.5",
        "retry_backoff" => "exponential",
        "on_error" => "stop"
      }

      assert NodeSettings.from_params(params) ==
               {:ok, %{"retries" => 3, "retry_delay" => 1.5, "retry_backoff" => "exponential"}}

      assert NodeSettings.from_params(%{"retries" => "0", "on_error" => "stop"}) == {:ok, %{}}
    end

    test "reads the pinned data, and can unpin it" do
      params = %{"pin_output" => "success", "pin_data" => ~s({"result": [1, 2]})}

      assert {:ok, %{"pin" => %{"output" => "success", "data" => %{"result" => [1, 2]}}}} =
               NodeSettings.from_params(params)

      assert NodeSettings.from_params(Map.put(params, "unpin", "true")) == {:ok, %{}}
    end

    test "refuses pinned data that isn't a JSON object" do
      params = %{"pin_output" => "exec", "pin_data" => "[1, 2]"}
      assert NodeSettings.from_params(params) == {:error, :invalid_pin}
    end

    test "keeps values within what a node takes" do
      assert {:ok, %{"retries" => 10}} = NodeSettings.from_params(%{"retries" => "40"})
    end
  end

  test "own_error_output?/1 knows the nodes with an error output of their own" do
    assert NodeSettings.own_error_output?("HTTP Request")
    refute NodeSettings.own_error_output?("Evaluate Code")
    refute NodeSettings.own_error_output?("Gone")
  end
end
