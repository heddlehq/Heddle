defmodule HeddleUI.MCP.Tools.PublishFlow do
  @moduledoc """
  Publishes a flow: from then on, its webhooks, schedules and the API run what it has
  now, its draft. With version_id, it puts that older version back in production
  instead, leaving the draft as it is. This changes what production runs, so the user
  is asked to confirm first. Test the draft with test_flow before publishing it.
  """

  use Anubis.Server.Component,
    type: :tool,
    name: "publish_flow",
    annotations: %{destructiveHint: true, openWorldHint: true}

  alias HeddleCore.Flows.Versions
  alias HeddleUI.AgentChat
  alias HeddleUI.MCP.Tool
  alias HeddleUI.PublicAPI.V1.VersionJSON

  schema do
    field :flow_id, :string, required: true, description: "Flow id"
    field :note, :string, description: "What changed, for whoever reads the history"
    field :version_id, :string, description: "An older version to publish instead of the draft"
  end

  @impl true
  def execute(%{flow_id: id} = params, frame) do
    Tool.authorize(frame, "workflows:write", fn scope ->
      Tool.with_flow(scope, id, frame, fn flow ->
        attrs = %{"note" => params[:note]}

        result =
          case params[:version_id] do
            blank when blank in [nil, ""] ->
              with :ok <- AgentChat.confirm_publish(frame.assigns.api_key, flow) do
                Versions.publish(scope, flow, attrs)
              end

            version_id ->
              with %{} = version <-
                     Versions.get_version(scope, flow, version_id) || {:error, :not_found},
                   :ok <- AgentChat.confirm_publish(frame.assigns.api_key, flow, version.number) do
                Versions.publish_version(scope, flow, version.id, attrs)
              end
          end

        case result do
          {:ok, version} -> Tool.reply(VersionJSON.graph(version, version.id) |> summary(), frame)
          {:error, :forbidden} -> Tool.forbidden(frame)
          {:error, :not_found} -> Tool.error("That version was not found.", frame)
          {:error, message} when is_binary(message) -> Tool.error(message, frame)
          {:error, reason} -> Tool.changeset_error(reason, frame)
        end
      end)
    end)
  end

  # The graph is what the model sent or already read, so it doesn't need it again.
  defp summary(version), do: Map.drop(version, [:nodes, :connections, :comments])
end
