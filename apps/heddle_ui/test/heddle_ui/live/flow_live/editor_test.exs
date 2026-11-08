defmodule HeddleUI.FlowLive.EditorTest do
  use HeddleUI.ConnCase, async: true
  use Oban.Testing, repo: HeddleCore.Repo

  import Phoenix.LiveViewTest
  import HeddleCore.FlowsFixtures
  import HeddleCore.AccountsFixtures

  alias HeddleCore.Executions
  alias HeddleCore.Flows

  @flow_execution_worker "HeddleWorker.FlowExecutionWorker"

  setup %{conn: conn} do
    admin = system_admin_fixture()
    Process.put(:heddle_owner, admin)
    %{conn: log_in_user(conn, admin), user: admin}
  end

  describe "roles" do
    defp open_as(flow, role) do
      user = user_fixture()
      member_fixture(HeddleCore.Workspaces.get_workspace(flow.workspace_id), user, role)
      conn = Phoenix.ConnTest.build_conn() |> log_in_user(user)
      {:ok, lv, html} = live(conn, ~p"/flows/#{flow.id}")
      {lv, html}
    end

    test "a viewer sees the flow, read only, and can't run or change it" do
      flow = flow_fixture(%{name: "Read me"})
      {lv, html} = open_as(flow, "viewer")

      assert html =~ "Read me"
      assert has_element?(lv, "#flow-read-only")
      assert has_element?(lv, "#flow-canvas[data-read-only='true']")
      refute has_element?(lv, "#canvas-tools")
      refute has_element?(lv, "button[phx-click='run_flow']")
      refute has_element?(lv, "#chat-component")

      render_hook(lv, "save_graph_data", %{"data" => %{"name" => "Changed"}})
      assert Flows.get_flow!(flow.id).name == "Read me"

      render_hook(lv, "save_and_run", %{"data" => %{"nodes" => [], "connections" => []}})
      assert Executions.list_executions_for_flow(flow) == []
    end

    test "an operator runs the flow as saved, without changing it" do
      flow =
        flow_fixture(%{
          name: "Run me",
          nodes: [%{"id" => "1", "type" => "Start", "controls" => %{}}]
        })

      {lv, _html} = open_as(flow, "operator")

      assert has_element?(lv, "button[phx-click='run_flow']")

      html =
        render_hook(lv, "save_and_run", %{
          "data" => %{"name" => "Changed", "nodes" => [], "connections" => []}
        })

      assert html =~ "Run inspector"
      assert has_element?(lv, "#run-inspector-status", "Queued")
      assert [execution] = Executions.list_executions_for_flow(flow)
      assert execution.input["debug"] == true
      assert Flows.get_flow!(flow.id).name == "Run me"

      # Only those who can change the flow see its settings.
      refute has_element?(lv, "#open-flow-settings")
    end

    test "an editor changes the flow" do
      flow = flow_fixture(%{name: "Edit me"})
      {lv, html} = open_as(flow, "editor")

      refute html =~ "View only"
      assert has_element?(lv, "#canvas-tools")

      render_hook(lv, "save_graph_data", %{"data" => %{"name" => "Edited"}})
      assert Flows.get_flow!(flow.id).name == "Edited"
    end

    test "opening a flow of another of the person's workspaces makes it theirs" do
      user = user_fixture()
      first = workspace_fixture(user)
      second = workspace_fixture(user)
      flow = flow_fixture(%{user: user, workspace: first})

      assert HeddleCore.Accounts.Scope.for_user(HeddleCore.Repo.reload!(user)).workspace.id ==
               second.id

      {:ok, _lv, _html} =
        Phoenix.ConnTest.build_conn() |> log_in_user(user) |> live(~p"/flows/#{flow.id}")

      assert HeddleCore.Accounts.Scope.for_user(HeddleCore.Repo.reload!(user)).workspace.id ==
               first.id
    end
  end

  describe "mount" do
    test "requires authentication" do
      conn = Phoenix.ConnTest.build_conn()
      flow = flow_fixture()

      assert {:error, redirect} = live(conn, ~p"/flows/#{flow.id}")
      assert {:redirect, %{to: path}} = redirect
      assert path == ~p"/users/log-in"
    end

    test "a flow of a workspace the person isn't in looks missing" do
      user = user_fixture()
      flow = flow_fixture()

      conn =
        Phoenix.ConnTest.build_conn()
        |> Phoenix.ConnTest.init_test_session(%{})
        |> log_in_user(user)

      assert_raise Ecto.NoResultsError, fn -> live(conn, ~p"/flows/#{flow.id}") end
    end

    test "loads flow and displays its name", %{conn: conn} do
      flow = flow_fixture(%{name: "My Awesome Flow"})

      {:ok, _lv, html} = live(conn, ~p"/flows/#{flow.id}")

      assert html =~ "My Awesome Flow"
      assert html =~ "Heddle"
    end

    test "shows node sidebar with categories", %{conn: conn} do
      flow = flow_fixture()

      {:ok, _lv, html} = live(conn, ~p"/flows/#{flow.id}")

      assert html =~ "Nodes"
      assert html =~ "Start"
      assert html =~ "Evaluate Code"
      assert html =~ "Variable"
      assert html =~ "Output"
      assert html =~ "Logger"
    end

    test "shows node descriptions as hover titles", %{conn: conn} do
      flow = flow_fixture()

      {:ok, lv, _html} = live(conn, ~p"/flows/#{flow.id}")

      assert has_element?(
               lv,
               ~s([data-node-name="Evaluate Code"][title="Runs Elixir or Python code with access to the current flow context."])
             )

      assert has_element?(
               lv,
               ~s([data-node-name=Logger][title="Writes a message to the application logs without changing the flow context."])
             )
    end

    test "filters nodes in the sidebar", %{conn: conn} do
      flow = flow_fixture()

      {:ok, lv, _html} = live(conn, ~p"/flows/#{flow.id}")

      lv
      |> form("#node-sidebar-search-form", node_search: %{query: "Eval"})
      |> render_change()

      assert has_element?(lv, ~s([data-node-name="Evaluate Code"]))
      refute has_element?(lv, ~s([data-node-name="Logger"]))
    end

    test "collapses and expands node categories", %{conn: conn} do
      flow = flow_fixture()

      {:ok, lv, _html} = live(conn, ~p"/flows/#{flow.id}")

      assert has_element?(lv, "#node-category-code [data-node-name=\"Evaluate Code\"]")

      render_click(lv, "toggle_node_category", %{"category" => "code"})
      refute has_element?(lv, "#node-category-code [data-node-name=\"Evaluate Code\"]")

      render_click(lv, "toggle_node_category", %{"category" => "code"})
      assert has_element?(lv, "#node-category-code [data-node-name=\"Evaluate Code\"]")
    end

    test "shows recently used nodes after adding a node", %{conn: conn} do
      flow = flow_fixture()

      {:ok, lv, _html} = live(conn, ~p"/flows/#{flow.id}")

      refute has_element?(lv, "#recent-node-group")

      render_click(lv, "add_node", %{"name" => "Variable"})

      assert has_element?(lv, "#recent-node-group [data-node-name=Variable]")
    end

    test "clears the recently used nodes", %{conn: conn} do
      flow = flow_fixture()

      {:ok, lv, _html} = live(conn, ~p"/flows/#{flow.id}")

      render_click(lv, "add_node", %{"name" => "Variable"})
      lv |> element("#clear-recent-nodes") |> render_click()

      refute has_element?(lv, "#recent-node-group")
      assert has_element?(lv, "#node-category-data_manipulation [data-node-name=Variable]")
    end

    test "groups the database nodes by store", %{conn: conn} do
      flow = flow_fixture()

      {:ok, lv, _html} = live(conn, ~p"/flows/#{flow.id}")

      refute has_element?(lv, "#node-category-database [data-node-name=\"SQL: Run Query\"]")

      render_click(lv, "toggle_node_category", %{"category" => "database"})

      assert has_element?(lv, "#node-category-database [data-node-name=\"SQL: Run Query\"]")
      assert has_element?(lv, "#node-category-database [id=\"node-group-SQL\"]")
      assert has_element?(lv, "#node-category-database [id=\"node-group-MongoDB\"]")
    end

    test "groups HTTP Request under HTTP", %{conn: conn} do
      flow = flow_fixture()

      {:ok, lv, _html} = live(conn, ~p"/flows/#{flow.id}")

      assert has_element?(lv, "#node-category-http button", "HTTP")
      assert has_element?(lv, "#node-category-http [data-node-name=\"HTTP Request\"]")
      refute has_element?(lv, "#node-category-integration")
    end

    test "renders the canvas container", %{conn: conn} do
      flow = flow_fixture()

      {:ok, _lv, html} = live(conn, ~p"/flows/#{flow.id}")

      assert html =~ ~s(id="flow-canvas-container")
      assert html =~ ~s(id="flow-canvas")
      assert html =~ ~s(phx-hook="FlowCanvas")
    end

    test "renders header action buttons", %{conn: conn} do
      flow = flow_fixture()

      {:ok, _lv, html} = live(conn, ~p"/flows/#{flow.id}")

      assert html =~ "Run Flow"
      assert html =~ "Flows"
    end
  end

  describe "flow name renaming" do
    test "enter rename mode and cancel", %{conn: conn} do
      flow = flow_fixture(%{name: "Original Name"})

      {:ok, lv, html} = live(conn, ~p"/flows/#{flow.id}")

      assert html =~ "Original Name"
      refute html =~ ~s(id="flow-name-input")

      html = render_click(lv, "edit_flow_name")
      assert html =~ ~s(id="flow-name-input")

      html = render_click(lv, "cancel_rename_flow")
      refute html =~ ~s(id="flow-name-input")
      assert html =~ "Original Name"
    end

    test "renames flow successfully", %{conn: conn} do
      flow = flow_fixture(%{name: "Old Name"})

      {:ok, lv, _html} = live(conn, ~p"/flows/#{flow.id}")

      render_click(lv, "edit_flow_name")

      html = render_submit(lv, "save_flow_name", %{"name" => "New Name"})
      assert html =~ "New Name"
      refute html =~ ~s(id="flow-name-input")

      updated_flow = HeddleCore.Flows.get_flow!(flow.id)
      assert updated_flow.name == "New Name"
    end

    test "does not rename with empty name", %{conn: conn} do
      flow = flow_fixture(%{name: "Keep This"})

      {:ok, lv, _html} = live(conn, ~p"/flows/#{flow.id}")

      render_click(lv, "edit_flow_name")
      html = render_submit(lv, "save_flow_name", %{"name" => "  "})

      assert html =~ "Keep This"
    end
  end

  describe "client_ready event" do
    test "pushes load_graph_data with nodes and connections", %{conn: conn} do
      flow =
        flow_fixture(%{
          name: "Graph Flow",
          nodes: [
            %{"id" => "1", "type" => "Start", "label" => "Start", "controls" => %{}},
            %{
              "id" => "2",
              "type" => "Variable",
              "label" => "Variable",
              "controls" => %{"var_name" => "x", "var_value" => "42", "var_type" => "Integer"}
            }
          ],
          connections: [
            %{"source" => "1", "sourceOutput" => "exec", "target" => "2", "targetInput" => "exec"}
          ]
        })

      {:ok, lv, _html} = live(conn, ~p"/flows/#{flow.id}")

      assert render_hook(lv, "client_ready", %{})
    end
  end

  describe "add_node event" do
    test "pushes add_node event for Start node", %{conn: conn} do
      flow = flow_fixture()

      {:ok, lv, _html} = live(conn, ~p"/flows/#{flow.id}")

      render_click(lv, "add_node", %{"name" => "Start"})
    end

    test "pushes add_node event for Evaluate Code node", %{conn: conn} do
      flow = flow_fixture()

      {:ok, lv, _html} = live(conn, ~p"/flows/#{flow.id}")

      render_click(lv, "add_node", %{"name" => "Evaluate Code"})
    end

    test "pushes add_node event for Variable node", %{conn: conn} do
      flow = flow_fixture()

      {:ok, lv, _html} = live(conn, ~p"/flows/#{flow.id}")

      render_click(lv, "add_node", %{"name" => "Variable"})
    end
  end

  describe "show_drag_tooltip event" do
    test "handles show_drag_tooltip without crashing", %{conn: conn} do
      flow = flow_fixture()

      {:ok, lv, _html} = live(conn, ~p"/flows/#{flow.id}")

      render_click(lv, "show_drag_tooltip", %{"name" => "Logger"})
    end
  end

  describe "graph_changed event" do
    test "marks flow as having unsaved changes", %{conn: conn} do
      flow = flow_fixture()

      {:ok, lv, html} = live(conn, ~p"/flows/#{flow.id}")

      refute html =~ "unsaved changes"

      html = render_hook(lv, "graph_changed", %{})
      assert html =~ "unsaved changes"
      assert html =~ "Save Changes"
    end
  end

  describe "node_added_internally event" do
    test "marks has_changes after node added", %{conn: conn} do
      flow = flow_fixture()

      {:ok, lv, html} = live(conn, ~p"/flows/#{flow.id}")

      refute html =~ "unsaved changes"

      html = render_hook(lv, "node_added_internally", %{"name" => "Start", "data" => %{}})
      assert html =~ "unsaved changes"
    end
  end

  describe "comments" do
    @comment %{
      "id" => "note",
      "kind" => "note",
      "color" => "yellow",
      "text" => "Calls the billing API",
      "width" => 240,
      "height" => 140,
      "position" => %{"x" => 10, "y" => 20}
    }

    test "can be added from the canvas, of every kind", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/flows/#{flow_fixture().id}")

      for kind <- ~w(title text note section) do
        assert has_element?(lv, "#add-comment-#{kind}[data-comment-kind=#{kind}]")
      end
    end

    test "are sent to the canvas", %{conn: conn} do
      flow = flow_fixture(%{comments: [@comment]})
      {:ok, lv, _html} = live(conn, ~p"/flows/#{flow.id}")

      render_hook(lv, "client_ready", %{})

      assert_push_event(lv, "load_graph_data", %{comments: [@comment]})
    end

    test "are saved with the graph, and that doesn't reload the canvas", %{conn: conn} do
      flow = flow_fixture()
      {:ok, lv, _html} = live(conn, ~p"/flows/#{flow.id}")

      render_hook(lv, "save_graph_data", %{
        "data" => %{"nodes" => [], "connections" => [], "comments" => [@comment]}
      })

      render(lv)

      assert Flows.get_flow!(flow.id).comments == [@comment]
      refute_push_event(lv, "load_graph_data", %{comments: [@comment]})
    end

    test "reload the canvas when changed elsewhere", %{conn: conn} do
      flow = flow_fixture()
      {:ok, lv, _html} = live(conn, ~p"/flows/#{flow.id}")

      {:ok, _flow} = Flows.update_flow(flow, %{comments: [@comment]})
      render(lv)

      assert_push_event(lv, "load_graph_data", %{comments: [@comment]})
    end
  end

  describe "importing a flow" do
    @imported %{
      "nodes" => [
        %{
          "id" => "hook",
          "type" => "Webhook",
          "label" => "New lead",
          "controls" => %{"method" => "POST", "path" => "/leads"},
          "position" => %{"x" => 0, "y" => 0}
        },
        %{
          "id" => "tell",
          "type" => "Slack: Send Message",
          "label" => "Tell sales",
          "controls" => %{"credential" => "99", "channel" => "#sales", "text" => "New lead"},
          "position" => %{"x" => 200, "y" => 0}
        }
      ],
      "connections" => [
        %{
          "source" => "hook",
          "sourceOutput" => "exec",
          "target" => "tell",
          "targetInput" => "exec"
        }
      ]
    }

    test "has a button that asks before replacing a flow with nodes", %{conn: conn} do
      empty = flow_fixture()
      {:ok, lv, _html} = live(conn, ~p"/flows/#{empty.id}")
      assert has_element?(lv, ~s(#import-flow[phx-hook="ImportFlow"][data-replace="false"]))

      full =
        flow_fixture(%{
          nodes: [%{"id" => "s", "type" => "Start", "label" => "Start", "controls" => %{}}]
        })

      {:ok, lv, _html} = live(conn, ~p"/flows/#{full.id}")
      assert has_element?(lv, ~s(#import-flow[data-replace="true"]))
    end

    test "puts the flow on the canvas unsaved, without its credentials", %{conn: conn} do
      flow = flow_fixture()
      {:ok, lv, _html} = live(conn, ~p"/flows/#{flow.id}")

      html = render_hook(lv, "import_flow", %{"json" => Jason.encode!(@imported)})

      assert_push_event(lv, "load_graph_data", %{nodes: nodes, connections: [_connection]})
      assert Enum.find(nodes, &(&1["id"] == "tell"))["controls"]["credential"] == ""
      assert html =~ "unsaved changes"
      assert has_element?(lv, "#flash-info", "Flow imported")
      assert HeddleCore.Flows.get_flow!(flow.id).nodes == []
    end

    test "says why a file can't be imported", %{conn: conn} do
      flow = flow_fixture()
      {:ok, lv, _html} = live(conn, ~p"/flows/#{flow.id}")

      render_hook(lv, "import_flow", %{"json" => "not json"})
      assert has_element?(lv, "#flash-error", "isn't JSON")

      render_hook(lv, "import_flow", %{"json" => ~s({"name": "Leads"})})
      assert has_element?(lv, "#flash-error", "isn't a Heddle flow")

      bad =
        put_in(@imported, ["connections"], [
          %{hd(@imported["connections"]) | "sourceOutput" => "nope"}
        ])

      html = render_hook(lv, "import_flow", %{"json" => Jason.encode!(bad)})
      assert has_element?(lv, "#flash-error", "can't be imported")
      refute html =~ "unsaved changes"

      render_hook(lv, "import_flow_too_big", %{})
      assert has_element?(lv, "#flash-error", "too big")
    end
  end

  describe "save_graph_data event" do
    test "saves graph data and clears has_changes", %{conn: conn} do
      flow = flow_fixture()

      {:ok, lv, _html} = live(conn, ~p"/flows/#{flow.id}")

      render_hook(lv, "graph_changed", %{})

      html =
        render_hook(lv, "save_graph_data", %{
          "data" => %{
            "nodes" => [
              %{
                "id" => "n1",
                "type" => "Start",
                "label" => "Start",
                "controls" => %{},
                "position" => %{"x" => 0, "y" => 0}
              }
            ],
            "connections" => []
          }
        })

      refute html =~ "unsaved changes"

      updated_flow = HeddleCore.Flows.get_flow!(flow.id)
      assert length(updated_flow.nodes) == 1
      assert hd(updated_flow.nodes)["type"] == "Start"
    end
  end

  describe "code of a node in the config drawer" do
    defp code_node(controls) do
      fields = %{
        "language" => %{
          "value" => "elixir",
          "label" => "Language",
          "type" => "select",
          "options" => ["elixir", "python"]
        },
        "code" => %{"value" => "", "label" => "Code Editor", "type" => "code-button"},
        "code_elixir" => %{"value" => "", "type" => "hidden"},
        "code_python" => %{"value" => "", "type" => "hidden"}
      }

      controls =
        Enum.reduce(controls, fields, fn {key, value}, acc ->
          put_in(acc, [key, "value"], value)
        end)

      %{"id" => "n1", "label" => "Eval", "type" => "Evaluate Code", "controls" => controls}
    end

    defp open_drawer(conn, controls) do
      {:ok, lv, _html} = live(conn, ~p"/flows/#{flow_fixture().id}")
      render_hook(lv, "open_node_config", %{"nodeId" => "n1", "nodeData" => code_node(controls)})
      lv
    end

    test "previews the code saved by the editor", %{conn: conn} do
      lv = open_drawer(conn, %{"code_elixir" => "3 + 3"})

      assert lv |> element("#node-code-preview-code") |> render() =~ "3 + 3"
    end

    test "previews the code of the node's language", %{conn: conn} do
      lv =
        open_drawer(conn, %{
          "language" => "python",
          "code_elixir" => "3 + 3",
          "code_python" => "print(42)"
        })

      preview = lv |> element("#node-code-preview-code") |> render()

      assert preview =~ "print(42)"
      refute preview =~ "3 + 3"
    end

    test "follows the language picked in the drawer", %{conn: conn} do
      lv = open_drawer(conn, %{"code_elixir" => "3 + 3", "code_python" => "print(42)"})

      lv |> form("#node-config-form", %{"language" => "python"}) |> render_change()

      assert lv |> element("#node-code-preview-code") |> render() =~ "print(42)"

      lv |> element("#edit-code-code") |> render_click()

      assert has_element?(lv, "#code-editor-wrapper[data-language=python]")
    end

    test "opens a Python node on its own tab with its code", %{conn: conn} do
      lv = open_drawer(conn, %{"language" => "python", "code_python" => "print(42)"})

      lv |> element("#edit-code-code") |> render_click()

      assert has_element?(lv, "#code-editor-wrapper[data-language=python]")
      assert lv |> element("#code_python_textarea") |> render() =~ "print(42)"
    end

    test "opens a node that only has the older code field", %{conn: conn} do
      lv = open_drawer(conn, %{"code" => "1 + 1"})

      assert lv |> element("#node-code-preview-code") |> render() =~ "1 + 1"

      lv |> element("#edit-code-code") |> render_click()

      assert lv |> element("#code_elixir_textarea") |> render() =~ "1 + 1"
    end

    test "saving drops the older field, so cleared code doesn't come back", %{conn: conn} do
      lv = open_drawer(conn, %{"code" => "1 + 1"})

      lv |> element("#edit-code-code") |> render_click()
      render_submit(lv, "save_code", %{"code_elixir" => "", "code_python" => ""})

      refute lv |> element("#node-code-preview-code") |> render() =~ "1 + 1"
    end
  end

  describe "open_code_editor event" do
    test "opens code editor modal with full params", %{conn: conn} do
      flow = flow_fixture()

      {:ok, lv, _html} = live(conn, ~p"/flows/#{flow.id}")

      html =
        render_hook(lv, "open_code_editor", %{
          "nodeId" => "node_1",
          "fieldName" => "code",
          "language" => "elixir",
          "code_elixir" => "IO.puts(\"hello\")",
          "code_python" => "print('hello')",
          "variables" => ["x", "y"]
        })

      assert html =~ "IO.puts"
    end

    test "opens code editor with minimal params", %{conn: conn} do
      flow = flow_fixture()

      {:ok, lv, _html} = live(conn, ~p"/flows/#{flow.id}")

      render_hook(lv, "open_code_editor", %{
        "nodeId" => "node_1",
        "code" => "1 + 1"
      })
    end

    test "closes code editor modal", %{conn: conn} do
      flow = flow_fixture()

      {:ok, lv, _html} = live(conn, ~p"/flows/#{flow.id}")

      render_hook(lv, "open_code_editor", %{
        "nodeId" => "node_1",
        "code" => "1 + 1"
      })

      render_click(lv, "close_modal")
    end
  end

  describe "save_code event" do
    test "saves code and closes modal", %{conn: conn} do
      flow = flow_fixture()

      {:ok, lv, _html} = live(conn, ~p"/flows/#{flow.id}")

      render_hook(lv, "open_code_editor", %{
        "nodeId" => "node_1",
        "fieldName" => "code",
        "language" => "elixir",
        "code_elixir" => "",
        "code_python" => ""
      })

      render_click(lv, "save_code", %{
        "code_elixir" => "IO.puts(:updated)",
        "code_python" => "print('updated')"
      })
    end

    test "saves code while config modal is open", %{conn: conn} do
      flow = flow_fixture()

      {:ok, lv, _html} = live(conn, ~p"/flows/#{flow.id}")

      render_hook(lv, "open_node_config", %{
        "nodeId" => "n1",
        "nodeData" => %{
          "id" => "n1",
          "label" => "Evaluate Code",
          "controls" => %{
            "code_elixir" => %{"value" => "old code", "type" => "code-button"},
            "code_python" => %{"value" => "", "type" => "code-button"},
            "code" => %{"value" => "old code", "type" => "code-button"}
          }
        }
      })

      render_hook(lv, "open_code_editor", %{
        "nodeId" => "n1",
        "fieldName" => "code",
        "language" => "elixir",
        "code_elixir" => "old code",
        "code_python" => ""
      })

      render_click(lv, "save_code", %{
        "code_elixir" => "new_code()",
        "code_python" => ""
      })
    end
  end

  describe "switch_code_tab event" do
    test "switches between elixir and python tabs", %{conn: conn} do
      flow = flow_fixture()

      {:ok, lv, _html} = live(conn, ~p"/flows/#{flow.id}")

      render_hook(lv, "open_code_editor", %{
        "nodeId" => "n1",
        "fieldName" => "code",
        "language" => "elixir",
        "code_elixir" => "IO.puts(:hi)",
        "code_python" => "print('hi')"
      })

      render_click(lv, "switch_code_tab", %{"tab" => "python"})
      render_click(lv, "switch_code_tab", %{"tab" => "elixir"})
    end
  end

  describe "open_node_config / save_node_config / close_config_modal" do
    test "opens config modal with node data", %{conn: conn} do
      flow = flow_fixture()

      {:ok, lv, _html} = live(conn, ~p"/flows/#{flow.id}")

      html =
        render_hook(lv, "open_node_config", %{
          "nodeId" => "n1",
          "nodeData" => %{
            "id" => "n1",
            "label" => "My Logger",
            "controls" => %{
              "level" => %{
                "value" => "info",
                "type" => "select",
                "label" => "Level",
                "options" => [
                  %{"label" => "Info", "value" => "info"},
                  %{"label" => "Error", "value" => "error"}
                ]
              },
              "message" => %{
                "value" => "hello",
                "type" => "text",
                "label" => "Message"
              }
            }
          }
        })

      assert html =~ "My Logger"
      assert html =~ "Node Name"
      assert html =~ "Save"
      assert html =~ "Cancel"
    end

    test "saves node config and closes modal", %{conn: conn} do
      flow = flow_fixture()

      {:ok, lv, _html} = live(conn, ~p"/flows/#{flow.id}")

      render_hook(lv, "open_node_config", %{
        "nodeId" => "n1",
        "nodeData" => %{
          "id" => "n1",
          "label" => "My Logger",
          "controls" => %{
            "message" => %{"value" => "hello", "type" => "text", "label" => "Message"}
          }
        }
      })

      render_submit(lv, "save_node_config", %{
        "node_label" => "Renamed Logger",
        "message" => "updated message"
      })

      refute has_element?(lv, "[phx-click=close_config_modal]")
    end

    test "closes config modal without saving", %{conn: conn} do
      flow = flow_fixture()

      {:ok, lv, _html} = live(conn, ~p"/flows/#{flow.id}")

      render_hook(lv, "open_node_config", %{
        "nodeId" => "n1",
        "nodeData" => %{
          "id" => "n1",
          "label" => "Some Node",
          "controls" => %{}
        }
      })

      html = render_click(lv, "close_config_modal")
      refute html =~ "Some Node"
    end

    test "shows 'no configuration' for node without controls", %{conn: conn} do
      flow = flow_fixture()

      {:ok, lv, _html} = live(conn, ~p"/flows/#{flow.id}")

      html =
        render_hook(lv, "open_node_config", %{
          "nodeId" => "s1",
          "nodeData" => %{
            "id" => "s1",
            "label" => "Start",
            "controls" => nil
          }
        })

      assert html =~ "No configuration options"
    end

    test "saves how the node behaves when it fails", %{conn: conn} do
      flow = flow_fixture()

      {:ok, lv, _html} = live(conn, ~p"/flows/#{flow.id}")

      render_hook(lv, "open_node_config", %{
        "nodeId" => "n1",
        "nodeData" => %{
          "id" => "n1",
          "type" => "Evaluate Code",
          "label" => "Code",
          "controls" => %{},
          "settings" => %{"retries" => 2}
        }
      })

      assert has_element?(lv, "#node-settings-retries[value=\"2\"]")
      # Code has no error output of its own, so it can be given one.
      assert has_element?(lv, "#node-settings-on-error-output")

      render_change(lv, "node_config_changed", %{"settings" => %{"retries" => "0"}})
      assert has_element?(lv, "#node-settings-delay[disabled]")

      render_submit(lv, "save_node_config", %{
        "node_label" => "Code",
        "settings" => %{"retries" => "3", "retry_delay" => "2", "on_error" => "continue"}
      })

      assert_push_event(lv, "update_node_settings", %{
        nodeId: "n1",
        settings: %{"retries" => 3, "retry_delay" => 2, "on_error" => "continue"}
      })
    end

    test "edits and unpins the data pinned to a node", %{conn: conn} do
      flow = flow_fixture()

      {:ok, lv, _html} = live(conn, ~p"/flows/#{flow.id}")

      render_hook(lv, "open_node_config", %{
        "nodeId" => "n1",
        "nodeData" => %{
          "id" => "n1",
          "type" => "HTTP Request",
          "label" => "API",
          "controls" => %{},
          "settings" => %{"pin" => %{"output" => "success", "data" => %{"result" => 1}}}
        }
      })

      assert has_element?(lv, "#node-settings-pin")
      refute has_element?(lv, "#node-settings-on-error-output")

      # Unpinning shows only once saved.
      render_change(lv, "node_config_changed", %{
        "settings" => %{"pin_output" => "success", "pin_data" => "{}", "unpin" => "true"}
      })

      assert has_element?(lv, "#node-settings-unpin[checked]")

      html =
        render_submit(lv, "save_node_config", %{
          "node_label" => "API",
          "settings" => %{"pin_output" => "success", "pin_data" => "not json"}
        })

      assert html =~ "The pinned data must be a JSON object."

      render_submit(lv, "save_node_config", %{
        "node_label" => "API",
        "settings" => %{"pin_output" => "success", "pin_data" => "{}", "unpin" => "true"}
      })

      assert_push_event(lv, "update_node_settings", %{nodeId: "n1", settings: settings})
      assert settings == %{}
    end
  end

  describe "flow settings" do
    test "picks the flow that runs when a run fails", %{conn: conn} do
      flow = flow_fixture(%{name: "Orders"})
      alerts = flow_fixture(%{name: "Alerts"})

      {:ok, lv, _html} = live(conn, ~p"/flows/#{flow.id}")

      lv |> element("#open-flow-settings") |> render_click()
      assert has_element?(lv, "#flow-settings-modal option", "Alerts")
      refute has_element?(lv, "#flow-settings-modal option", "Orders")

      lv
      |> form("#flow-settings-form", flow_settings: %{error_flow_id: alerts.id})
      |> render_submit()

      refute has_element?(lv, "#flow-settings-modal")
      assert Flows.get_flow!(flow.id).error_flow_id == alerts.id
    end
  end

  describe "create_node_modal" do
    test "opens and closes the create node modal", %{conn: conn} do
      flow = flow_fixture()

      {:ok, lv, _html} = live(conn, ~p"/flows/#{flow.id}")

      refute has_element?(lv, "[phx-click=close_create_node_modal]")

      render_hook(lv, "open_create_node_modal", %{"x" => 200, "y" => 300})

      assert has_element?(lv, "[phx-click=close_create_node_modal]")
      assert has_element?(lv, "[phx-click=create_node_from_modal][phx-value-name=Start]")

      assert has_element?(
               lv,
               "[phx-click=create_node_from_modal][phx-value-name=\"Evaluate Code\"]"
             )

      render_click(lv, "close_create_node_modal")
      refute has_element?(lv, "[phx-click=close_create_node_modal]")
    end

    test "creates node from modal", %{conn: conn} do
      flow = flow_fixture()

      {:ok, lv, _html} = live(conn, ~p"/flows/#{flow.id}")

      render_hook(lv, "open_create_node_modal", %{"x" => 100, "y" => 100})

      render_click(lv, "create_node_from_modal", %{"name" => "Variable"})
      refute has_element?(lv, "[phx-click=close_create_node_modal]")
    end

    test "filters nodes by search query", %{conn: conn} do
      flow = flow_fixture()

      {:ok, lv, _html} = live(conn, ~p"/flows/#{flow.id}")

      render_hook(lv, "open_create_node_modal", %{"x" => 100, "y" => 100})

      render_hook(lv, "filter_nodes", %{"value" => "Eval"})

      assert has_element?(
               lv,
               "[phx-click=create_node_from_modal][phx-value-name=\"Evaluate Code\"]"
             )

      refute has_element?(lv, "[phx-click=create_node_from_modal][phx-value-name=Logger]")

      render_hook(lv, "filter_nodes", %{"value" => ""})
      assert has_element?(lv, "[phx-click=create_node_from_modal][phx-value-name=Logger]")

      assert has_element?(
               lv,
               "[phx-click=create_node_from_modal][phx-value-name=\"Evaluate Code\"]"
             )
    end
  end

  describe "save_and_run queueing" do
    test "creates a manual execution and enqueues the Oban worker", %{conn: conn} do
      flow =
        flow_fixture(%{
          nodes: [
            %{"id" => "1", "type" => "Start", "label" => "Start", "controls" => %{}},
            %{
              "id" => "2",
              "type" => "Output",
              "label" => "Output",
              "controls" => %{"status" => "done"}
            }
          ],
          connections: [
            %{"source" => "1", "sourceOutput" => "exec", "target" => "2", "targetInput" => "exec"}
          ]
        })

      {:ok, lv, _html} = live(conn, ~p"/flows/#{flow.id}")

      html =
        render_hook(lv, "save_and_run", %{
          "data" => %{
            "nodes" => flow.nodes,
            "connections" => flow.connections
          }
        })

      assert html =~ "Run inspector"
      assert has_element?(lv, "#run-inspector-status", "Queued")
      refute has_element?(lv, "#execution-queue-notice")

      assert [execution] = Executions.list_executions_for_flow(flow)
      assert execution.status == "queued"
      # A run from the editor takes the pinned data and reports each step.
      assert execution.input == %{"trigger" => "manual", "debug" => true}
      assert html =~ execution.public_id
      # The inspector opens as a bar, and shows the run when opened.
      refute has_element?(lv, "#run-timeline")
      render_click(lv, "inspector_toggle")
      assert has_element?(lv, "#run-timeline-waiting")

      assert_enqueued(
        worker: @flow_execution_worker,
        queue: :executions,
        args: %{execution_id: execution.id}
      )

      render_click(lv, "inspector_close")
      refute has_element?(lv, "#run-inspector")
    end

    test "once the inspector is closed, the run reports through the notice", %{conn: conn} do
      flow = flow_fixture()

      {:ok, lv, _html} = live(conn, ~p"/flows/#{flow.id}")

      render_hook(lv, "save_and_run", %{
        "data" => %{"nodes" => flow.nodes, "connections" => flow.connections}
      })

      assert [execution] = Executions.list_executions_for_flow(flow)
      render_click(lv, "inspector_close")

      {:ok, execution} = Executions.mark_succeeded(execution, %{"result" => 1})
      send(lv.pid, {:execution_updated, execution})

      assert has_element?(lv, "#execution-queue-notice", "Execution finished")

      lv |> element("#open-execution-result") |> render_click()

      assert has_element?(lv, "#run-inspector-status", "Succeeded")
      refute has_element?(lv, "#execution-queue-notice")
    end

    test "follows the run step by step, then shows what it saved", %{conn: conn} do
      flow = flow_fixture()

      {:ok, lv, _html} = live(conn, ~p"/flows/#{flow.id}")

      render_hook(lv, "save_and_run", %{
        "data" => %{"nodes" => flow.nodes, "connections" => flow.connections}
      })

      assert [execution] = Executions.list_executions_for_flow(flow)

      step = %{
        "node_id" => "1",
        "node_type" => "Start",
        "status" => "success",
        "output" => "exec",
        "started_at" => "2026-11-08T10:00:00.000000Z",
        "duration_ms" => 1.5,
        "data" => %{"input" => %{"trigger" => "manual"}, "output" => %{}}
      }

      render_click(lv, "inspector_toggle")
      send(lv.pid, {:execution_step, execution.id, step})
      send(lv.pid, :inspector_flush)

      assert has_element?(lv, "#run-step-0", "Start")
      assert has_element?(lv, "#run-inspector-status", "Running")

      failed = %{
        "node_id" => "2",
        "node_type" => "Output",
        "label" => "Finish",
        "status" => "error",
        "output" => "error",
        "error" => "it broke",
        "attempts" => 3,
        "retry_errors" => ["first", "second"],
        "started_at" => "2026-11-08T10:00:00.002000Z",
        "duration_ms" => 3.0,
        "data" => %{"input" => %{"trigger" => "manual"}, "output" => %{}}
      }

      {:ok, execution} =
        Executions.mark_failed(execution, %{"message" => "it broke", "node_id" => "2"}, %{
          logs: [step, failed]
        })

      send(lv.pid, {:execution_updated, execution})

      assert has_element?(lv, "#run-inspector-status", "Failed")
      # A failed run opens at the step that failed, on its error.
      assert has_element?(lv, "#run-step-name", "Finish")
      assert has_element?(lv, "#run-step-error", "it broke")
      assert has_element?(lv, "#run-step-error", "second")

      lv |> element("#run-step-0") |> render_click()
      assert has_element?(lv, "#run-step-name", "Start")
      assert has_element?(lv, "#run-json-0-output") == false
      assert has_element?(lv, "#run-tab-input")

      lv |> element("#run-tab-input") |> render_click()
      assert has_element?(lv, "json-tree#run-json-0-input")

      lv |> element("#run-step-result") |> render_click()
      assert has_element?(lv, "#run-step-detail", "it broke")
    end

    test "runs again with the input of the run, and from a step with what it got",
         %{conn: conn} do
      flow = flow_fixture()

      {:ok, execution} =
        Executions.create_execution(%{
          flow_id: flow.id,
          input: %{"trigger" => "manual", "name" => "Ana"},
          logs: [
            %{
              "node_id" => "1",
              "node_type" => "Start",
              "status" => "success",
              "output" => "exec",
              "data" => %{"input" => %{"name" => "Ana", "result" => 1}, "output" => %{}}
            }
          ]
        })

      {:ok, lv, _html} = live(conn, ~p"/flows/#{flow.id}?execution=#{execution.public_id}")
      render_hook(lv, "client_ready", %{})

      assert has_element?(lv, "#run-inspector")
      refute has_element?(lv, "#run-step-detail")

      # Picking the node on the canvas opens the panel at its step.
      render_hook(lv, "inspector_select_node", %{"node_id" => "1"})
      assert has_element?(lv, "#run-step-name", "Start")

      lv |> element("#run-step-replay") |> render_click()
      assert_push_event(lv, "request_save_and_run", %{})

      render_hook(lv, "save_and_run", %{
        "data" => %{"nodes" => flow.nodes, "connections" => flow.connections}
      })

      assert %{input: input} =
               flow
               |> Executions.list_executions_for_flow()
               |> Enum.find(&(&1.id != execution.id))

      assert input == %{"name" => "Ana", "result" => 1, "replay_from" => "1", "debug" => true}
    end

    test "pins the output of a step to its node on the canvas", %{conn: conn} do
      flow = flow_fixture()

      {:ok, execution} =
        Executions.create_execution(%{
          flow_id: flow.id,
          logs: [
            %{
              "node_id" => "1",
              "node_type" => "Start",
              "status" => "success",
              "output" => "exec",
              "data" => %{"input" => %{}, "output" => %{"result" => 42}}
            }
          ]
        })

      {:ok, lv, _html} = live(conn, ~p"/flows/#{flow.id}?execution=#{execution.public_id}")
      render_hook(lv, "client_ready", %{})
      render_hook(lv, "inspector_select_node", %{"node_id" => "1"})

      lv |> element("#run-step-pin") |> render_click()

      assert_push_event(lv, "pin_node", %{
        nodeId: "1",
        pin: %{"output" => "exec", "data" => %{"result" => 42}}
      })
    end

    test "queues execution without running runtime errors inside the LiveView", %{conn: conn} do
      flow =
        flow_fixture(%{
          nodes: [
            %{"id" => "1", "type" => "Start", "label" => "Start", "controls" => %{}},
            %{
              "id" => "2",
              "type" => "Evaluate Code",
              "label" => "Evaluate Code",
              "controls" => %{
                "code_elixir" => "raise \"boom\"",
                "language" => "elixir"
              }
            }
          ],
          connections: [
            %{
              "source" => "1",
              "sourceOutput" => "exec",
              "target" => "2",
              "targetInput" => "exec"
            }
          ]
        })

      {:ok, lv, _html} = live(conn, ~p"/flows/#{flow.id}")

      html =
        render_hook(lv, "save_and_run", %{
          "data" => %{"nodes" => flow.nodes, "connections" => flow.connections}
        })

      assert html =~ "Run inspector"
      assert has_element?(lv, "#run-inspector-status", "Queued")
      refute has_element?(lv, "#execution-queue-notice")

      assert [execution] = Executions.list_executions_for_flow(flow)

      assert_enqueued(
        worker: @flow_execution_worker,
        queue: :executions,
        args: %{execution_id: execution.id}
      )
    end
  end

  describe "testing a webhook" do
    setup %{conn: conn} do
      user = system_admin_fixture()
      Process.put(:heddle_owner, user)
      flow = flow_fixture()
      {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/flows/#{flow.id}")

      %{lv: lv, flow: flow}
    end

    defp entry_node(type) do
      %{
        "id" => "entry",
        "type" => type,
        "label" => type,
        "controls" => %{},
        "position" => %{"x" => 0, "y" => 0}
      }
    end

    defp run_with(lv, type) do
      data = %{"nodes" => [entry_node(type)], "connections" => []}
      render_hook(lv, "save_and_run", %{"data" => data})
    end

    test "asks for the request instead of running with none", %{lv: lv, flow: flow} do
      run_with(lv, "Webhook")

      assert has_element?(lv, "#webhook-test-form")
      assert HeddleCore.Executions.list_executions_for_flow(flow) == []
    end

    test "runs a flow with a Start right away", %{lv: lv, flow: flow} do
      run_with(lv, "Start")

      refute has_element?(lv, "#webhook-test-form")

      assert [%{input: %{"trigger" => "manual"}}] =
               HeddleCore.Executions.list_executions_for_flow(flow)
    end

    test "sends what was typed as the request", %{lv: lv, flow: flow} do
      run_with(lv, "Webhook")

      lv
      |> form("#webhook-test-form")
      |> render_submit(%{webhook_test: %{method: "PUT", body: ~s({"x": 2})}})

      assert_push_event(lv, "request_save_and_run", %{})
      refute has_element?(lv, "#webhook-test-form")

      run_with(lv, "Webhook")

      assert [%{input: input}] = HeddleCore.Executions.list_executions_for_flow(flow)

      assert %{"trigger" => "webhook", "request" => %{"method" => "PUT", "body" => %{"x" => 2}}} =
               input
    end

    test "asks again on the next run, with the last body", %{lv: lv} do
      run_with(lv, "Webhook")

      lv
      |> form("#webhook-test-form")
      |> render_submit(%{webhook_test: %{method: "POST", body: ~s({"x": 7})}})

      run_with(lv, "Webhook")
      run_with(lv, "Webhook")

      assert lv
             |> element("#webhook-test-form input[type=hidden][name='webhook_test[body]']")
             |> render() =~ "7"
    end

    test "suggests the fields the flow reads", %{lv: lv} do
      code = %{"code_elixir" => ~s|variable(:body)["x"] * variable(:body)["y"]|}
      eval = %{entry_node("Evaluate Code") | "id" => "eval", "controls" => code}
      data = %{"nodes" => [entry_node("Webhook"), eval], "connections" => []}

      render_hook(lv, "save_and_run", %{"data" => data})

      assert lv |> element("#webhook-body-editor") |> render() =~ "[&quot;x&quot;,&quot;y&quot;]"
    end

    test "says when the body isn't JSON", %{lv: lv} do
      run_with(lv, "Webhook")

      lv
      |> form("#webhook-test-form")
      |> render_submit(%{webhook_test: %{method: "POST", body: "{nope"}})

      assert has_element?(lv, "#webhook-test-error")
    end
  end

  describe "running a section" do
    setup %{conn: conn} do
      user = system_admin_fixture()
      Process.put(:heddle_owner, user)
      flow = flow_fixture()
      {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/flows/#{flow.id}")

      %{lv: lv, flow: flow}
    end

    defp section_data(type) do
      node = %{
        "id" => "entry",
        "type" => type,
        "label" => type,
        "controls" => %{},
        "position" => %{"x" => 0, "y" => 0}
      }

      section = %{
        "id" => "billing",
        "kind" => "section",
        "color" => "default",
        "text" => "Billing",
        "position" => %{"x" => -20, "y" => -20},
        "width" => 520,
        "height" => 320,
        "manual" => true,
        "nodes" => ["entry"]
      }

      %{"nodes" => [node], "connections" => [], "comments" => [section]}
    end

    test "saves the flow and runs that section alone", %{lv: lv, flow: flow} do
      render_hook(lv, "run_section", %{"section_id" => "billing", "data" => section_data("Start")})

      assert [%{input: %{"trigger" => "section", "section_id" => "billing"}}] =
               Executions.list_executions_for_flow(flow)

      assert [%{"manual" => true, "nodes" => ["entry"]}] =
               HeddleCore.Flows.get_flow!(flow.id).comments
    end

    test "asks for the request when the section starts at a Webhook", %{lv: lv, flow: flow} do
      data = section_data("Webhook")
      render_hook(lv, "run_section", %{"section_id" => "billing", "data" => data})

      assert has_element?(lv, "#webhook-test-form")

      lv
      |> form("#webhook-test-form")
      |> render_submit(%{webhook_test: %{method: "POST", body: ~s({"x": 1})}})

      assert_push_event(lv, "request_save_and_run", %{})
      render_hook(lv, "save_and_run", %{"data" => data})

      assert [%{input: %{"trigger" => "webhook", "section_id" => "billing"}}] =
               Executions.list_executions_for_flow(flow)
    end

    test "forgets the section when the request is not sent", %{lv: lv, flow: flow} do
      render_hook(lv, "run_section", %{
        "section_id" => "billing",
        "data" => section_data("Webhook")
      })

      render_click(lv, "close_webhook_test")

      data = %{section_data("Start") | "comments" => []}
      render_hook(lv, "save_and_run", %{"data" => data})

      assert [%{input: %{"trigger" => "manual"} = input}] =
               Executions.list_executions_for_flow(flow)

      refute Map.has_key?(input, "section_id")
    end

    test "a Start in a manual section doesn't count when the whole flow runs", %{lv: lv} do
      %{"nodes" => [start], "comments" => [section]} = section_data("Start")
      hook = %{start | "id" => "hook", "type" => "Webhook", "label" => "Webhook"}
      data = %{"nodes" => [start, hook], "connections" => [], "comments" => [section]}

      render_hook(lv, "save_and_run", %{"data" => data})

      assert has_element?(lv, "#webhook-test-form")
    end
  end

  describe "save_and_run with errors" do
    test "queues execution even when the flow has no Start node", %{conn: conn} do
      flow =
        flow_fixture(%{
          nodes: [
            %{
              "id" => "1",
              "type" => "Output",
              "label" => "Output",
              "controls" => %{"status" => "ok"}
            }
          ],
          connections: []
        })

      {:ok, lv, _html} = live(conn, ~p"/flows/#{flow.id}")

      html =
        render_hook(lv, "save_and_run", %{
          "data" => %{"nodes" => flow.nodes, "connections" => flow.connections}
        })

      assert html =~ "Run inspector"
      assert has_element?(lv, "#run-inspector-status", "Queued")
      refute has_element?(lv, "#execution-queue-notice")

      assert [execution] = Executions.list_executions_for_flow(flow)

      assert_enqueued(
        worker: @flow_execution_worker,
        queue: :executions,
        args: %{execution_id: execution.id}
      )
    end
  end

  describe "save_and_run full pipeline" do
    test "queues Start -> Variable -> Output flow", %{conn: conn} do
      flow =
        flow_fixture(%{
          nodes: [
            %{"id" => "1", "type" => "Start", "label" => "Start", "controls" => %{}},
            %{
              "id" => "2",
              "type" => "Variable",
              "label" => "Variable",
              "controls" => %{
                "var_name" => "counter",
                "var_value" => "10",
                "var_type" => "Integer"
              }
            },
            %{
              "id" => "3",
              "type" => "Output",
              "label" => "Output",
              "controls" => %{"status" => "complete"}
            }
          ],
          connections: [
            %{
              "source" => "1",
              "sourceOutput" => "exec",
              "target" => "2",
              "targetInput" => "exec"
            },
            %{"source" => "2", "sourceOutput" => "exec", "target" => "3", "targetInput" => "exec"}
          ]
        })

      {:ok, lv, _html} = live(conn, ~p"/flows/#{flow.id}")

      html =
        render_hook(lv, "save_and_run", %{
          "data" => %{"nodes" => flow.nodes, "connections" => flow.connections}
        })

      assert html =~ "Run inspector"
      assert has_element?(lv, "#run-inspector-status", "Queued")
      refute has_element?(lv, "#execution-queue-notice")

      assert [execution] = Executions.list_executions_for_flow(flow)

      assert_enqueued(
        worker: @flow_execution_worker,
        queue: :executions,
        args: %{execution_id: execution.id}
      )
    end

    test "queues Start -> Evaluate Code -> Output flow", %{conn: conn} do
      flow =
        flow_fixture(%{
          nodes: [
            %{"id" => "1", "type" => "Start", "label" => "Start", "controls" => %{}},
            %{
              "id" => "2",
              "type" => "Evaluate Code",
              "label" => "Evaluate Code",
              "controls" => %{
                "code_elixir" => "Map.put(context, \"result\", 42)",
                "language" => "elixir"
              }
            },
            %{
              "id" => "3",
              "type" => "Output",
              "label" => "Output",
              "controls" => %{"status" => "success"}
            }
          ],
          connections: [
            %{
              "source" => "1",
              "sourceOutput" => "exec",
              "target" => "2",
              "targetInput" => "exec"
            },
            %{"source" => "2", "sourceOutput" => "exec", "target" => "3", "targetInput" => "exec"}
          ]
        })

      {:ok, lv, _html} = live(conn, ~p"/flows/#{flow.id}")

      html =
        render_hook(lv, "save_and_run", %{
          "data" => %{"nodes" => flow.nodes, "connections" => flow.connections}
        })

      assert html =~ "Run inspector"
      assert has_element?(lv, "#run-inspector-status", "Queued")
      refute has_element?(lv, "#execution-queue-notice")

      assert [execution] = Executions.list_executions_for_flow(flow)

      assert_enqueued(
        worker: @flow_execution_worker,
        queue: :executions,
        args: %{execution_id: execution.id}
      )
    end
  end

  describe "get_node_definition event" do
    test "handles get_node_definition without crashing", %{conn: conn} do
      flow = flow_fixture()

      {:ok, lv, _html} = live(conn, ~p"/flows/#{flow.id}")

      render_hook(lv, "get_node_definition", %{"name" => "Start"})
    end
  end

  describe "parse_node_ui event" do
    test "handles parse_node_ui without crashing", %{conn: conn} do
      flow = flow_fixture()

      {:ok, lv, _html} = live(conn, ~p"/flows/#{flow.id}")

      render_hook(lv, "parse_node_ui", %{
        "code" => """
        ui do
          input "data_in"
          output "data_out"
        end
        """
      })
    end
  end

  describe "switch_language event" do
    test "switches code language", %{conn: conn} do
      flow = flow_fixture()

      {:ok, lv, _html} = live(conn, ~p"/flows/#{flow.id}")

      render_click(lv, "switch_language", %{"lang" => "python"})
      render_click(lv, "switch_language", %{"lang" => "elixir"})
    end
  end

  describe "chat toggle" do
    test "toggles chat panel open and closed", %{conn: conn} do
      flow = flow_fixture()

      {:ok, lv, _html} = live(conn, ~p"/flows/#{flow.id}")

      render_click(lv, "toggle_chat")
      render_click(lv, "toggle_chat")
    end
  end

  describe "change_locale event" do
    test "redirects when locale changes", %{conn: conn} do
      flow = flow_fixture()

      {:ok, lv, _html} = live(conn, ~p"/flows/#{flow.id}")

      render_click(lv, "change_locale", %{"locale" => "pt_BR"})
      assert_redirect(lv, "/?locale=pt_BR")
    end
  end
end
