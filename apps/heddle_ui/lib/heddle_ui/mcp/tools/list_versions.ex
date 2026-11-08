defmodule HeddleUI.MCP.Tools.ListVersions do
  @moduledoc """
  Lists the versions of a flow, newest first: its number, kind (publish, checkpoint or
  run), whether it is live (what production runs), who made it and changed it, its
  note and what it changed from the one before. The flow itself is the draft:
  webhooks, schedules and the API run the live version, until the draft is published.
  """

  use Anubis.Server.Component,
    type: :tool,
    name: "list_versions",
    annotations: %{readOnlyHint: true}

  alias HeddleCore.Flows.Versions
  alias HeddleUI.MCP.Tool
  alias HeddleUI.PublicAPI.V1.VersionJSON

  schema do
    field :flow_id, :string, required: true, description: "Flow id"
  end

  @impl true
  def execute(%{flow_id: id}, frame) do
    Tool.authorize(frame, "workflows:read", fn scope ->
      Tool.with_flow(scope, id, frame, fn flow ->
        case Versions.list_versions(scope, flow) do
          {:ok, entries} ->
            Tool.reply(
              %{versions: Enum.map(entries, &VersionJSON.entry(&1, flow.published_version_id))},
              frame
            )

          {:error, reason} ->
            Tool.changeset_error(reason, frame)
        end
      end)
    end)
  end
end
