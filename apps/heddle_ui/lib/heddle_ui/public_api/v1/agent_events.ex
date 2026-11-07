defmodule HeddleUI.PublicAPI.V1.AgentEvents do
  @moduledoc """
  Writes the events of the agent as server-sent events.
  """

  def snapshot(transcript), do: format("snapshot", transcript)

  def event(%{type: type} = event), do: format(type, event)

  # Comment lines keep proxies from closing a stream that is quiet for a while.
  def keep_alive, do: ": keep-alive\n\n"

  defp format(name, data), do: "event: #{name}\ndata: #{Jason.encode!(data)}\n\n"
end
