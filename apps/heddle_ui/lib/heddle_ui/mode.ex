defmodule HeddleUI.Mode do
  @moduledoc """
  Runtime mode helpers for the UI application.
  """

  @valid_modes ~w(full api)

  def mode do
    mode = System.get_env("HEDDLE_UI_MODE", "full")

    if mode in @valid_modes do
      mode
    else
      raise """
      invalid HEDDLE_UI_MODE=#{inspect(mode)}.
      Expected one of: #{Enum.join(@valid_modes, ", ")}
      """
    end
  end

  def full?, do: mode() == "full"
  def api?, do: mode() == "api"

  def endpoint do
    if api?() do
      HeddleUI.ApiEndpoint
    else
      HeddleUI.Endpoint
    end
  end
end
