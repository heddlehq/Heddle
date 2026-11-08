defmodule HeddleUI.MCP.Server do
  @moduledoc """
  MCP server that lets clients read and edit flows, or talk to the Heddle agent.

  It sits behind `HeddleUI.Plugs.ApiKeyAuth`, so every tool runs as the owner of the
  API key and within its scopes. There is deliberately no tool to delete a flow.
  """

  use Anubis.Server,
    name: "heddle",
    version: "1.0.0",
    capabilities: [:tools]

  alias HeddleUI.MCP.Tools

  component(Tools.ListFlows)
  component(Tools.GetFlow)
  component(Tools.CreateFlow)
  component(Tools.UpdateFlow)
  component(Tools.ListNodes)
  component(Tools.ListExecutions)
  component(Tools.GetExecution)
  component(Tools.RunFlow)
  component(Tools.TestFlow)
  component(Tools.ListVersions)
  component(Tools.PublishFlow)
  component(Tools.RestoreVersion)
  component(Tools.Chat)

  # Long enough for a person to answer a confirmation before the request gives up.
  def request_timeout, do: to_timeout(minute: 6)
end
