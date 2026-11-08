defmodule Heddle.Graph.SettingsTest do
  use ExUnit.Case, async: true

  alias Heddle.Graph.Settings

  test "a node without settings takes the defaults" do
    assert %Settings{retries: 0, retry_delay: 0, on_error: "stop", pin: nil} = Settings.new(nil)
  end

  test "reads what is stored, and keeps values within their limits" do
    settings = Settings.new(%{"retries" => 50, "retry_delay" => -1, "on_error" => "continue"})

    assert settings.retries == 10
    assert settings.retry_delay == 0
    assert settings.on_error == "continue"
  end

  test "valid?/1 accepts only the keys and values a node takes" do
    assert Settings.valid?(nil)
    assert Settings.valid?(%{"retries" => 3, "retry_delay" => 2.5, "on_error" => "output"})
    assert Settings.valid?(%{"pin" => %{"output" => "exec", "data" => %{"result" => 1}}})

    refute Settings.valid?(%{"retries" => 11})
    refute Settings.valid?(%{"retries" => "3"})
    refute Settings.valid?(%{"on_error" => "explode"})
    refute Settings.valid?(%{"pin" => %{"data" => %{}}})
    refute Settings.valid?(%{"color" => "red"})
    refute Settings.valid?("retries")
  end

  test "delay/2 doubles with an exponential backoff, and never waits more than 5 minutes" do
    fixed = Settings.new(%{"retry_delay" => 2})
    exponential = Settings.new(%{"retry_delay" => 2, "retry_backoff" => "exponential"})

    assert Enum.map(2..4, &Settings.delay(fixed, &1)) == [2000, 2000, 2000]
    assert Enum.map(2..4, &Settings.delay(exponential, &1)) == [2000, 4000, 8000]
    assert Settings.delay(exponential, 12) == 300_000
  end

  test "error_output?/1 says whether the settings give the node an error output" do
    assert Settings.error_output?(%{"on_error" => "output"})
    refute Settings.error_output?(%{"on_error" => "continue"})
    refute Settings.error_output?(nil)
  end
end
