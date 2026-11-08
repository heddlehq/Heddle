defmodule HeddleUI.PublicAPI.V1.VersionController do
  @moduledoc """
  The versions of a workflow: listing them, publishing the draft or an older version,
  and restoring one into the draft. See `HeddleCore.Flows.Versions`.
  """

  use HeddleUI, :controller

  alias HeddleCore.Flows
  alias HeddleCore.Flows.{Version, Versions}
  alias HeddleUI.PublicAPI.V1.WorkflowJSON

  action_fallback HeddleUI.FallbackController

  plug HeddleUI.Plugs.RequireApiScope, ["workflows:read"] when action in [:index, :show]

  plug HeddleUI.Plugs.RequireApiScope,
       ["workflows:write"] when action in [:publish, :publish_version, :restore]

  def index(conn, %{"workflow_id" => workflow_id}) do
    with {:ok, workflow} <- fetch(conn, workflow_id),
         {:ok, entries} <- Versions.list_versions(conn.assigns.current_scope, workflow) do
      render(conn, :index, entries: entries, published_id: workflow.published_version_id)
    end
  end

  def show(conn, %{"workflow_id" => workflow_id, "id" => id}) do
    with {:ok, workflow} <- fetch(conn, workflow_id),
         %Version{} = version <-
           Versions.get_version(conn.assigns.current_scope, workflow, id) || {:error, :not_found} do
      render(conn, :show, version: version, published_id: workflow.published_version_id)
    end
  end

  def publish(conn, %{"workflow_id" => workflow_id} = params) do
    with {:ok, workflow} <- fetch(conn, workflow_id),
         {:ok, version} <-
           Versions.publish(conn.assigns.current_scope, workflow, Map.take(params, ["note"])) do
      conn
      |> put_status(:created)
      |> render(:show, version: version, published_id: version.id)
    end
  end

  def publish_version(conn, %{"workflow_id" => workflow_id, "id" => id} = params) do
    with {:ok, workflow} <- fetch(conn, workflow_id),
         {:ok, version} <-
           Versions.publish_version(
             conn.assigns.current_scope,
             workflow,
             id,
             Map.take(params, ["note"])
           ) do
      conn
      |> put_status(:created)
      |> render(:show, version: version, published_id: version.id)
    end
  end

  def restore(conn, %{"workflow_id" => workflow_id, "id" => id}) do
    with {:ok, workflow} <- fetch(conn, workflow_id),
         {:ok, workflow} <- Versions.restore(conn.assigns.current_scope, workflow, id) do
      conn
      |> put_view(json: WorkflowJSON)
      |> render(:show, workflow: workflow)
    end
  end

  defp fetch(conn, id) do
    case Flows.get_flow(conn.assigns.current_scope, id) do
      nil -> {:error, :not_found}
      workflow -> {:ok, workflow}
    end
  end
end
