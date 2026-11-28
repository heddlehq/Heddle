defmodule HeddleUI.Plugs.IntegrationHookPlugTest do
  # Swaps the credential store and installs a community integration, both global.
  use HeddleUI.ConnCase, async: false

  import HeddleCore.AccountsFixtures
  import HeddleCore.FlowsFixtures
  import HeddleCore.IntegrationsFixtures

  alias HeddleCore.Executions
  alias HeddleCore.Integrations.Hooks

  defmodule Vault do
    def fetch(_workspace_id, "forge", "forge"),
      do: {:ok, %{"token" => "t0k", "signing_secret" => "whsec"}}
  end

  setup do
    previous = Application.get_env(:heddle_nodes, :credentials_client)
    Application.put_env(:heddle_nodes, :credentials_client, Vault)
    on_exit(fn -> Application.put_env(:heddle_nodes, :credentials_client, previous) end)
    on_exit(&HeddleNodes.Community.reset/0)

    user = user_fixture()
    workspace = workspace_fixture(user)
    install_forge(user_scope_fixture(user))

    %{user: user, workspace: workspace}
  end

  defp hooked_flow(%{user: user, workspace: workspace}, type, controls) do
    flow =
      flow_fixture(%{
        user: user,
        workspace: workspace,
        nodes: [
          %{
            "id" => "trigger",
            "type" => type,
            "label" => "Trigger",
            "controls" => Map.put(controls, "credential", "forge"),
            "position" => %{"x" => 0, "y" => 0}
          }
        ]
      })

    hook =
      Hooks.save(flow.id, "trigger", Hooks.new_token(), %{
        type: type,
        controls: controls,
        webhook: %{"secret" => "s3cr3t", "id" => "42"}
      })

    {flow, hook}
  end

  defp deliver(conn, hook, body, headers, query \\ "") do
    conn =
      Enum.reduce(headers, conn, fn {key, value}, conn -> put_req_header(conn, key, value) end)

    conn
    |> put_req_header("content-type", "application/json")
    |> post("/hooks/#{hook.token}#{query}", body)
  end

  test "an event the service signed starts the flow once per item", %{conn: conn} = context do
    {flow, hook} = hooked_flow(context, "Forge: New Push", %{"repo" => "acme"})
    body = ~s({"commits": [{"id": "a"}, {"id": "b"}]})

    conn = deliver(conn, hook, body, [{"x-forge-signature", sign("s3cr3t", body)}])

    assert %{"received" => 2, "started" => 2} = json_response(conn, 200)

    items =
      flow
      |> Executions.list_executions_for_flow()
      |> Enum.map(& &1.input)

    assert Enum.sort_by(items, & &1["item"]["id"]) == [
             %{"trigger" => "hook", "node_id" => "trigger", "item" => %{"id" => "a"}},
             %{"trigger" => "hook", "node_id" => "trigger", "item" => %{"id" => "b"}}
           ]
  end

  test "an event with a wrong signature starts nothing", %{conn: conn} = context do
    {flow, hook} = hooked_flow(context, "Forge: New Push", %{"repo" => "acme"})
    body = ~s({"commits": [{"id": "a"}]})

    conn = deliver(conn, hook, body, [{"x-forge-signature", sign("other", body)}])

    assert json_response(conn, 401)
    assert Executions.list_executions_for_flow(flow) == []
  end

  test "the signature can use a secret of the credential", %{conn: conn} = context do
    {flow, hook} = hooked_flow(context, "Forge: New Payment", %{})
    body = ~s({"amount": 10})
    signature = :crypto.mac(:hmac, :sha256, "whsec", body) |> Base.encode16(case: :lower)

    conn = deliver(conn, hook, body, [{"pay-signature", signature}])

    assert %{"started" => 1} = json_response(conn, 200)
    assert [%{input: %{"item" => %{"amount" => 10}}}] = Executions.list_executions_for_flow(flow)
  end

  test "a service that checks the address first gets its challenge back",
       %{conn: conn} = context do
    {flow, hook} = hooked_flow(context, "Forge: New Payment", %{})

    conn = get(conn, "/hooks/#{hook.token}?hub.challenge=abc123")

    assert response(conn, 200) == "abc123"
    assert Executions.list_executions_for_flow(flow) == []
  end

  test "an unknown address, or a node the published flow no longer has, is not found",
       %{conn: conn} = context do
    assert json_response(deliver(conn, %{token: "nope"}, "{}", []), 404)

    {flow, hook} = hooked_flow(context, "Forge: New Push", %{"repo" => "acme"})
    {:ok, flow} = HeddleCore.Flows.update_flow(flow, %{nodes: []})
    {:ok, _version} = HeddleCore.Flows.Versions.publish_draft(flow, context.user.id)

    body = ~s({"commits": []})
    conn = deliver(build_conn(), hook, body, [{"x-forge-signature", sign("s3cr3t", body)}])
    assert json_response(conn, 404)
  end
end
