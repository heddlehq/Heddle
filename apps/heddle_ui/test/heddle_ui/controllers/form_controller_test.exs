defmodule HeddleUI.FormControllerTest do
  use HeddleUI.ConnCase, async: true

  import HeddleCore.AccountsFixtures
  import HeddleCore.FlowsFixtures

  alias HeddleCore.{Executions, Flows, Forms}
  alias HeddleCore.Flows.Versions

  @fields Jason.encode!([
            %{"key" => "name", "label" => "Your name", "type" => "text", "required" => true},
            %{
              "key" => "plan",
              "label" => "Plan",
              "type" => "select",
              "options" => ["Free", "Pro"]
            },
            %{"key" => "terms", "label" => "I agree", "type" => "checkbox"}
          ])

  defp form_node(controls \\ %{}) do
    %{
      "id" => "form",
      "type" => "Form Trigger",
      "label" => "Form",
      "controls" =>
        Map.merge(
          %{
            "title" => "Join us",
            "description" => "Tell us who you are",
            "fields" => @fields,
            "submit_label" => "Join",
            "success_message" => "Welcome aboard",
            "redirect_url" => "",
            "accepting" => "yes"
          },
          controls
        )
    }
  end

  setup do
    user = user_fixture()
    workspace = workspace_fixture(user)
    scope = user_scope_fixture(user)
    flow = flow_fixture(user: user, workspace: workspace, nodes: [form_node()])
    {:ok, form} = Forms.link(scope, flow, "form")
    %{user: user, scope: scope, flow: flow, token: form.token}
  end

  describe "the public page" do
    test "shows the published form", %{conn: conn, token: token} do
      html = conn |> get(~p"/f/#{token}") |> html_response(200)

      assert html =~ "Join us"
      assert html =~ "Tell us who you are"
      assert html =~ ~s(name="form[name]")
      assert html =~ ~s(data-theme-lock="system")
      assert html =~ "Join"
    end

    test "a token that isn't a form is not found", %{conn: conn} do
      assert conn |> get(~p"/f/nope") |> html_response(404) =~ "form-not-found"
    end

    test "sending it runs the published version", %{conn: conn, token: token, flow: flow} do
      html =
        conn
        |> post(~p"/f/#{token}", %{
          "form" => %{"name" => "Ana", "plan" => "Pro", "terms" => "true"}
        })
        |> html_response(200)

      assert html =~ "Welcome aboard"

      assert [execution] = Executions.list_executions_for_flow(flow.id)
      assert execution.input["form"] == %{"name" => "Ana", "plan" => "Pro", "terms" => true}
    end

    test "shows what to fix, and keeps what was typed", %{conn: conn, token: token, flow: flow} do
      html =
        conn
        |> post(~p"/f/#{token}", %{"form" => %{"name" => "", "plan" => "Gold"}})
        |> html_response(422)

      assert html =~ "Fill in this field."
      assert html =~ "Pick one of the options."
      assert Executions.list_executions_for_flow(flow.id) == []
    end

    test "shows by each field what a Validate of the flow refused, in the visitor's language",
         %{conn: conn, scope: scope, flow: flow} do
      {:ok, flow} =
        Flows.update_flow(flow, %{
          nodes: [
            form_node(),
            %{
              "id" => "check",
              "type" => "Validate",
              "label" => "Check",
              "position" => %{"x" => 200, "y" => 0},
              "controls" => %{
                "validation_data" => "{{form}}",
                "validation_schema" => ~s({"name": {"type": "string", "min": 3}})
              }
            }
          ],
          connections: [%{"source" => "form", "sourceOutput" => "exec", "target" => "check"}]
        })

      {:ok, _version} = Versions.publish(scope, flow)
      {:ok, form} = Forms.link(scope, flow, "form")

      # What the worker's run of the Validate answers.
      answering =
        Task.async(fn ->
          execution = await_execution(flow.id)

          Executions.put_response(execution, %{
            "form" => "invalid",
            "errors" => [
              %{
                "path" => "name",
                "code" => "too_small",
                "message" => "Must have at least 3 characters",
                "params" => %{"bound" => "min", "limit" => 3, "unit" => "characters"}
              },
              %{"path" => "", "code" => "custom", "message" => "Try again tomorrow"}
            ]
          })
        end)

      html =
        conn
        |> put_req_header("accept-language", "pt-BR")
        |> post(~p"/f/#{form.token}", %{"form" => %{"name" => "Al", "plan" => "Pro"}})
        |> html_response(422)

      Task.await(answering)

      document = LazyHTML.from_document(html)
      assert LazyHTML.text(LazyHTML.query(document, "#form-alert")) =~ "Try again tomorrow"
      assert html =~ "Use pelo menos 3 caracteres."
      assert LazyHTML.attribute(LazyHTML.query(document, "#form_name"), "value") == ["Al"]
    end

    test "a bot that fills the hidden field is told it worked, and runs nothing", %{
      conn: conn,
      token: token,
      flow: flow
    } do
      html =
        conn
        |> post(~p"/f/#{token}", %{"form" => %{"name" => "Bot"}, "website" => "spam.example"})
        |> html_response(200)

      assert html =~ "form-sent"
      assert Executions.list_executions_for_flow(flow.id) == []
    end

    test "too many sendings from one address wait a minute", %{conn: conn, token: token} do
      Application.put_env(:heddle_ui, :form_rate_limit, 0)
      on_exit(fn -> Application.delete_env(:heddle_ui, :form_rate_limit) end)

      html = conn |> post(~p"/f/#{token}", %{"form" => %{"name" => "Ana"}}) |> html_response(429)
      assert html =~ "Wait a minute"
    end

    test "goes to the redirect address after sending", %{
      conn: conn,
      scope: scope,
      flow: flow,
      token: token
    } do
      publish(scope, flow, form_node(%{"redirect_url" => "https://example.com/thanks"}))

      conn = post(conn, ~p"/f/#{token}", %{"form" => %{"name" => "Ana"}})
      assert redirected_to(conn) == "https://example.com/thanks"
    end

    test "a closed form takes no answers", %{conn: conn, scope: scope, flow: flow, token: token} do
      publish(scope, flow, form_node(%{"accepting" => "no"}))

      assert conn |> get(~p"/f/#{token}") |> html_response(200) =~ "form-closed"

      assert conn |> post(~p"/f/#{token}", %{"form" => %{"name" => "Ana"}}) |> html_response(200) =~
               "form-closed"
    end
  end

  describe "testing the draft" do
    test "runs the draft for someone signed in who can run the flow", %{
      conn: conn,
      user: user,
      scope: scope,
      flow: flow
    } do
      {:ok, _flow} =
        Flows.update_flow(scope, flow, %{"nodes" => [form_node(%{"title" => "Draft title"})]})

      conn = log_in_user(conn, user)

      html = conn |> get(~p"/flows/#{flow.id}/forms/form/test") |> html_response(200)
      assert html =~ "Draft title"
      assert html =~ "form-test-banner"

      html =
        conn
        |> post(~p"/flows/#{flow.id}/forms/form/test", %{"form" => %{"name" => "Ana"}})
        |> html_response(200)

      assert [execution] = Executions.list_executions_for_flow(flow.id)
      assert execution.flow_version_id != flow.published_version_id
      assert html =~ "/flows/#{flow.id}?execution=#{execution.public_id}"
    end

    test "is refused to a viewer and missing to others", %{conn: conn, flow: flow} do
      viewer = user_fixture()
      member_fixture(HeddleCore.Workspaces.get_workspace(flow.workspace_id), viewer, "viewer")

      assert conn
             |> log_in_user(viewer)
             |> get(~p"/flows/#{flow.id}/forms/form/test")
             |> html_response(403)

      stranger = user_fixture()
      workspace_fixture(stranger)

      assert Phoenix.ConnTest.build_conn()
             |> log_in_user(stranger)
             |> get(~p"/flows/#{flow.id}/forms/form/test")
             |> html_response(404)
    end

    test "needs someone signed in", %{conn: conn, flow: flow} do
      assert redirected_to(get(conn, ~p"/flows/#{flow.id}/forms/form/test")) == ~p"/users/log-in"
    end
  end

  defp publish(scope, flow, node) do
    {:ok, _flow} = Flows.update_flow(scope, flow, %{"nodes" => [node]})
    {:ok, _version} = Versions.publish(scope, flow)
  end

  defp await_execution(flow_id, tries \\ 200) do
    case Executions.list_executions_for_flow(flow_id) do
      [execution | _] ->
        execution

      [] when tries > 0 ->
        receive do
        after
          10 -> await_execution(flow_id, tries - 1)
        end
    end
  end
end
