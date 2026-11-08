defmodule HeddleUI.MCP.Tools.RestoreVersion do
  @moduledoc """
  Replaces the draft of a flow with what one of its versions had (see list_versions).
  The draft it has now is kept as a version first, so this can be undone. Production
  keeps running what is published until the flow is published again. The user is asked
  to confirm first.
  """

  use Anubis.Server.Component,
    type: :tool,
    name: "restore_version",
    annotations: %{destructiveHint: true}

  alias HeddleCore.Flows.Versions
  alias HeddleUI.AgentChat
  alias HeddleUI.MCP.Tool
  alias HeddleUI.PublicAPI.V1.WorkflowJSON

  schema do
    field :flow_id, :string, required: true, description: "Flow id"
    field :version_id, :string, required: true, description: "The version to restore"
  end

  @impl true
  def execute(%{flow_id: id, version_id: version_id}, frame) do
    Tool.authorize(frame, "workflows:write", fn scope ->
      Tool.with_flow(scope, id, frame, fn flow ->
        with %{} = version <-
               Versions.get_version(scope, flow, version_id) || {:error, :not_found},
             :ok <- AgentChat.confirm_restore(frame.assigns.api_key, flow, version.number),
             {:ok, flow} <- Versions.restore(scope, flow, version.id) do
          Tool.reply(WorkflowJSON.show(%{workflow: flow}).data, frame)
        else
          {:error, :forbidden} -> Tool.forbidden(frame)
          {:error, :not_found} -> Tool.error("That version was not found.", frame)
          {:error, message} when is_binary(message) -> Tool.error(message, frame)
          {:error, reason} -> Tool.changeset_error(reason, frame)
        end
      end)
    end)
  end
end
