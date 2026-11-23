defmodule HeddleUI.FlowLive.IntegrationEditorTest do
  # Swaps the credential store and installs a community integration, both global.
  use HeddleUI.ConnCase, async: false

  import Phoenix.LiveViewTest
  import HeddleCore.AccountsFixtures
  import HeddleCore.FlowsFixtures
  import HeddleCore.IntegrationsFixtures

  alias HeddleCore.Integrations.Hooks

  defmodule Vault do
    def fetch(_workspace_id, "forge", "forge"), do: {:ok, %{"token" => "t0k"}}
  end

  setup %{conn: conn} do
    previous = Application.get_env(:heddle_nodes, :credentials_client)
    Application.put_env(:heddle_nodes, :credentials_client, Vault)
    on_exit(fn -> Application.put_env(:heddle_nodes, :credentials_client, previous) end)
    on_exit(&HeddleNodes.Community.reset/0)

    user = user_fixture()
    workspace = workspace_fixture(user)
    install_forge(user_scope_fixture(user))

    %{conn: log_in_user(conn, user), user: user, workspace: workspace}
  end

  defp open(conn, flow, node) do
    {:ok, lv, _html} = live(conn, ~p"/flows/#{flow.id}")

    controls =
      Map.new(node["controls"], fn {key, value} ->
        {key,
         %{"value" => value, "type" => node["types"][key] || "text", "label" => key}
         |> Map.merge(node["extra"][key] || %{})}
      end)

    render_hook(lv, "open_node_config", %{
      "nodeId" => node["id"],
      "nodeData" => %{
        "id" => node["id"],
        "type" => node["type"],
        "label" => node["type"],
        "controls" => controls
      }
    })

    lv
  end

  defp flow(context, node) do
    flow_fixture(%{
      user: context.user,
      workspace: context.workspace,
      nodes: [Map.take(node, ~w(id type label controls)) |> Map.put("label", "n")]
    })
  end

  describe "a webhook trigger" do
    @push %{
      "id" => "push",
      "type" => "Forge: New Payment",
      "controls" => %{"credential" => "forge"},
      "types" => %{"credential" => "credential"}
    }

    test "shows its address once the flow is published and Heddle has it", context do
      flow = flow(context, @push)
      lv = open(context.conn, flow, @push)
      assert has_element?(lv, "#hook-link-unpublished")
      refute has_element?(lv, "#hook-link-url")

      # What HeddleWorker.HookWorker keeps for a trigger pasted by hand.
      hook =
        Hooks.save(flow.id, "push", Hooks.new_token(), %{
          type: "Forge: New Payment",
          controls: %{"credential" => "forge"},
          webhook: %{},
          manual: true
        })

      lv = open(context.conn, flow, @push)
      assert lv |> element("#hook-link-url") |> render() =~ Hooks.url(hook)
      assert render(lv) =~ "Paste this address in Forge"
      refute has_element?(lv, "#hook-link-unpublished")
    end
  end

  describe "an action" do
    @issue %{
      "id" => "issue",
      "type" => "Forge: Create Issue",
      "controls" => %{
        "credential" => "forge",
        "repo" => "",
        "title" => "",
        "draft" => "false",
        "labels" => ""
      },
      "types" => %{
        "credential" => "credential",
        "repo" => "select",
        "draft" => "boolean",
        "labels" => "multiselect"
      },
      "extra" => %{
        "repo" => %{"options_from" => true},
        "labels" => %{
          "options" => [
            %{"label" => "Bug", "value" => "bug"},
            %{"label" => "Docs", "value" => "docs"}
          ]
        }
      }
    }

    test "loads a field's options from the service, with the node's credential", context do
      Req.Test.stub(HeddleNodes.Nodes.HttpRequest, fn conn ->
        assert conn.request_path == "/repos"
        assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer t0k"]
        Req.Test.json(conn, %{"items" => [%{"name" => "Acme", "id" => "acme"}]})
      end)

      lv = open(context.conn, flow(context, @issue), @issue)
      assert has_element?(lv, "input#node-field-repo")

      lv |> element("#service-options-load-repo") |> render_click()

      assert has_element?(lv, ~s(select#node-field-repo option[value="acme"]), "Acme")
    end

    test "says why the options didn't load", context do
      Req.Test.stub(HeddleNodes.Nodes.HttpRequest, fn conn ->
        conn |> Plug.Conn.put_status(401) |> Req.Test.json(%{})
      end)

      lv = open(context.conn, flow(context, @issue), @issue)
      lv |> element("#service-options-load-repo") |> render_click()

      assert has_element?(lv, "#service-options-error-repo")
    end

    test "a multiselect sends a JSON list, and a boolean true or false", context do
      lv = open(context.conn, flow(context, @issue), @issue)

      lv
      |> element("#node-config-form")
      |> render_change(%{"labels" => ["", "bug", "docs"], "draft" => "true"})

      assert_push_event(lv, "update_node_data", %{data: %{"labels" => ~s(["bug","docs"])}})

      assert has_element?(lv, ~s(#node-field-labels input[value="bug"][checked]))
      assert has_element?(lv, ~s(input#node-field-draft[checked]))
    end

    test "labels come in the user's language when the manifest has it", context do
      Gettext.put_locale(HeddleUI.Gettext, "pt_BR")
      on_exit(fn -> Gettext.put_locale(HeddleUI.Gettext, "en") end)

      assert HeddleUI.FlowLive.IntegrationManager.label("Forge: Create Issue", "title", "Title") ==
               "Título"
    end
  end
end
