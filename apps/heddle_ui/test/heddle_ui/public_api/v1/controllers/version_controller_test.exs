defmodule HeddleUI.PublicAPI.V1.VersionControllerTest do
  use HeddleUI.ConnCase, async: true

  import HeddleCore.AccountsFixtures
  import HeddleCore.FlowsFixtures

  alias HeddleCore.Flows

  @start %{"id" => "1", "type" => "Start", "label" => "Start", "controls" => %{}}
  @output %{"id" => "2", "type" => "Output", "label" => "Output", "controls" => %{}}

  setup do
    user = user_fixture()
    workflow = flow_fixture(%{user: user, nodes: [@start]})
    %{user: user, workflow: workflow}
  end

  describe "index" do
    test "lists the versions, the live one marked", %{conn: conn, user: user, workflow: workflow} do
      conn =
        conn
        |> authorize(user, ["workflows:read"])
        |> get(~p"/api/v1/workflows/#{workflow.id}/versions")

      assert %{"data" => [version]} = json_response(conn, 200)
      assert version["number"] == 1
      assert version["kind"] == "publish"
      assert version["live"] == true
      assert version["changes"] == %{"nodes_added" => 1}
    end

    test "a workflow of another workspace looks missing", %{conn: conn, workflow: workflow} do
      conn =
        conn
        |> authorize(user_fixture(), ["workflows:read"])
        |> get(~p"/api/v1/workflows/#{workflow.id}/versions")

      assert json_response(conn, 404)
    end
  end

  describe "publish" do
    test "publishes the draft", %{conn: conn, user: user, workflow: workflow} do
      {:ok, _workflow} =
        Flows.update_flow(user_scope_fixture(user), workflow, %{nodes: [@start, @output]})

      conn =
        conn
        |> authorize(user, ["workflows:write"])
        |> post(~p"/api/v1/workflows/#{workflow.id}/publish", %{"note" => "Adds output"})

      assert %{
               "data" => %{
                 "number" => 2,
                 "live" => true,
                 "note" => "Adds output",
                 "nodes" => nodes
               }
             } =
               json_response(conn, 201)

      assert length(nodes) == 2
      assert Flows.get_flow!(workflow.id).published_version_id != workflow.published_version_id
    end

    test "needs the write scope", %{conn: conn, user: user, workflow: workflow} do
      conn =
        conn
        |> authorize(user, ["workflows:read"])
        |> post(~p"/api/v1/workflows/#{workflow.id}/publish")

      assert json_response(conn, 403)
    end

    test "a viewer may not publish", %{conn: conn, workflow: workflow} do
      viewer = user_fixture()
      member_fixture(HeddleCore.Workspaces.get_workspace(workflow.workspace_id), viewer, "viewer")

      conn =
        conn
        |> authorize(viewer, ["workflows:write"])
        |> post(~p"/api/v1/workflows/#{workflow.id}/publish")

      assert %{"error" => %{"code" => "forbidden"}} = json_response(conn, 403)
    end
  end

  describe "publishing and restoring a version" do
    test "puts an old version back, in production or in the draft", %{
      conn: conn,
      user: user,
      workflow: workflow
    } do
      scope = user_scope_fixture(user)
      first_id = workflow.published_version_id
      {:ok, workflow} = Flows.update_flow(scope, workflow, %{nodes: [@start, @output]})
      {:ok, _second} = HeddleCore.Flows.Versions.publish(scope, workflow)

      published =
        conn
        |> authorize(user, ["workflows:write"])
        |> post(~p"/api/v1/workflows/#{workflow.id}/versions/#{first_id}/publish")
        |> json_response(201)

      assert %{"data" => %{"number" => 3, "source_version_number" => 1}} = published
      assert length(Flows.get_flow!(workflow.id).nodes) == 2

      restored =
        build_conn()
        |> authorize(user, ["workflows:write"])
        |> post(~p"/api/v1/workflows/#{workflow.id}/versions/#{first_id}/restore")
        |> json_response(200)

      assert %{"data" => %{"nodes" => [%{"id" => "1"}]}} = restored
    end
  end

  describe "running" do
    test "production can't run a workflow that isn't published", %{conn: conn, user: user} do
      workflow = flow_fixture(%{user: user, nodes: [@start], published: false})

      conn =
        conn
        |> authorize(user, ["executions:write"])
        |> post(~p"/api/v1/workflows/#{workflow.id}/executions", %{"input" => %{}})

      assert %{"error" => %{"code" => "not_published"}} = json_response(conn, 409)
    end

    test "version=draft runs the draft", %{conn: conn, user: user} do
      workflow = flow_fixture(%{user: user, nodes: [@start], published: false})

      conn =
        conn
        |> authorize(user, ["executions:write"])
        |> post(~p"/api/v1/workflows/#{workflow.id}/executions", %{"version" => "draft"})

      assert %{"data" => %{"id" => _public_id}} = json_response(conn, 202)
    end
  end

  defp authorize(conn, user, scopes) do
    {:ok, %{token: token}} = create_api_key(user, %{name: "test key", scopes: scopes})
    put_req_header(conn, "authorization", "Bearer #{token}")
  end
end
