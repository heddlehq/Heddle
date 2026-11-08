defmodule HeddleCore.FormsTest do
  # The core doesn't know the nodes, so these tests set a manifest, which is global.
  use HeddleCore.DataCase, async: false

  import HeddleCore.AccountsFixtures
  import HeddleCore.FlowsFixtures

  alias HeddleCore.{Executions, Flows, Forms, Repo, Spool}
  alias HeddleCore.Executions.Execution
  alias HeddleCore.Flows.{GraphValidator, Versions}

  @fields Jason.encode!([
            %{"key" => "name", "label" => "Name", "type" => "text", "required" => true},
            %{"key" => "age", "label" => "Age", "type" => "number"},
            %{"key" => "terms", "label" => "Terms", "type" => "checkbox"}
          ])

  defp form_node(controls \\ %{}) do
    %{
      "id" => "form",
      "type" => "Form Trigger",
      "label" => "Form",
      "controls" =>
        Map.merge(
          %{
            "title" => "Sign up",
            "fields" => @fields,
            "success_message" => "Thanks",
            "accepting" => "yes"
          },
          controls
        )
    }
  end

  defmodule Manifest do
    def get_definitions, do: [%{name: "Form Trigger", inputs: [], outputs: ["exec"]}]
  end

  setup do
    previous = Application.get_env(:heddle_core, :graph_manifest)
    Application.put_env(:heddle_core, :graph_manifest, Manifest)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:heddle_core, :graph_manifest, previous),
        else: Application.delete_env(:heddle_core, :graph_manifest)
    end)

    unless oban_running?(),
      do: start_supervised!({Oban, name: HeddleCore.Oban, repo: Repo, testing: :manual})

    scope = user_scope_fixture()
    flow = flow_fixture(user: scope.user, workspace: scope.workspace, nodes: [form_node()])
    {:ok, form} = Forms.link(scope, flow, "form")
    %{scope: scope, flow: flow, form: form}
  end

  describe "link/3" do
    test "keeps the same link, and has none for another node", %{
      scope: scope,
      flow: flow,
      form: form
    } do
      assert {:ok, ^form} = Forms.link(scope, flow, "form")
      assert {:error, :not_found} = Forms.link(scope, flow, "nope")
      assert {:error, :forbidden} = Forms.link(user_scope_fixture(), flow, "form")
    end

    test "a publish makes the links of its forms", %{scope: scope} do
      flow = flow_fixture(user: scope.user, workspace: scope.workspace, nodes: [form_node()])
      assert [%{node_id: "form"}] = Forms.list_by_flow(flow.id)
    end

    test "only editors make a new link", %{scope: scope, flow: flow, form: form} do
      viewer = user_fixture()
      member_fixture(scope.workspace, viewer, "viewer")

      assert {:error, :forbidden} = Forms.regenerate(user_scope_fixture(viewer), flow, "form")
      assert {:ok, new} = Forms.regenerate(scope, flow, "form")
      assert new.token != form.token
      assert {:error, :not_found} = Forms.public(form.token)
      assert {:ok, _page} = Forms.public(new.token)
    end
  end

  describe "public/1 and submit/2" do
    test "shows what is published", %{form: form} do
      assert {:ok, %{title: "Sign up", fields: [%{"key" => "name"} | _]}} =
               Forms.public(form.token)

      assert {:error, :not_found} = Forms.public("nope")
      assert {:error, :not_found} = Forms.public(nil)
    end

    test "starts a run of the published version from the node", %{flow: flow, form: form} do
      assert {:ok, %{success_message: "Thanks"}} =
               Forms.submit(form.token, %{"name" => "Ana", "age" => "30", "terms" => "on"})

      assert [execution] = Repo.all(from e in Execution, where: e.flow_id == ^flow.id)
      assert execution.flow_version_id == flow.published_version_id

      assert %{
               "trigger" => "form",
               "node_id" => "form",
               "form" => %{"name" => "Ana", "age" => 30, "terms" => true}
             } = execution.input
    end

    test "says what is wrong, and runs nothing", %{flow: flow, form: form} do
      assert {:error, :invalid, _page, %{"name" => :required}, %{"age" => "x"}} =
               Forms.submit(form.token, %{"age" => "x"})

      assert Executions.list_executions_for_flow(flow.id) == []
    end

    test "a draft that isn't published doesn't show", %{scope: scope} do
      flow =
        flow_fixture(
          user: scope.user,
          workspace: scope.workspace,
          nodes: [form_node()],
          published: false
        )

      {:ok, form} = Forms.link(scope, flow, "form")
      assert {:error, :not_found} = Forms.public(form.token)
      assert {:error, :not_found} = Forms.submit(form.token, %{"name" => "Ana"})
    end

    test "a closed form shows, and takes nothing", %{scope: scope, flow: flow, form: form} do
      {:ok, _flow} =
        Flows.update_flow(scope, flow, %{"nodes" => [form_node(%{"accepting" => "no"})]})

      {:ok, _version} = Versions.publish(scope, flow)

      assert {:error, :closed, %{title: "Sign up"}} = Forms.public(form.token)
      assert {:error, :closed, _page} = Forms.submit(form.token, %{"name" => "Ana"})
    end

    test "only a web address is a redirect" do
      node = %Heddle.Graph.Node{
        id: "f",
        type: "Form Trigger",
        controls: %{"redirect_url" => "javascript:alert(1)"}
      }

      assert Forms.page(node).redirect_url == nil

      node = %{node | controls: %{"redirect_url" => " https://example.com/ok "}}
      assert Forms.page(node).redirect_url == "https://example.com/ok"
    end
  end

  describe "draft/3 and submit_draft/4" do
    test "run the draft for those who can run the flow", %{scope: scope, flow: flow} do
      {:ok, flow} =
        Flows.update_flow(scope, flow, %{"nodes" => [form_node(%{"title" => "Draft title"})]})

      assert {:ok, %{title: "Draft title"}} = Forms.draft(scope, flow, "form")
      assert {:ok, execution, _page} = Forms.submit_draft(scope, flow, "form", %{"name" => "Ana"})
      assert execution.flow_version_id != flow.published_version_id

      viewer = user_fixture()
      member_fixture(scope.workspace, viewer, "viewer")
      assert {:error, :forbidden} = Forms.draft(user_scope_fixture(viewer), flow, "form")
    end

    test "check what was sent", %{scope: scope, flow: flow} do
      assert {:error, :invalid, _page, %{"name" => :required}, _values} =
               Forms.submit_draft(scope, flow, "form", %{})
    end
  end

  test "create_table/4 makes a Spool table from the fields", %{scope: scope, flow: flow} do
    assert {:ok, table} = Forms.create_table(scope, flow, "form", "Sign ups")

    assert Enum.map(table.columns, &{&1["name"], &1["type"]}) == [
             {"name", "text"},
             {"age", "number"},
             {"terms", "boolean"}
           ]

    assert [_table] = Spool.list_tables(scope)
  end

  test "a draft may have unfinished fields, and publishing checks them" do
    nodes = [form_node(%{"fields" => "[]"})]

    assert :ok = GraphValidator.validate(nodes, [], draft: true)

    assert {:error, :nodes, "contains a Form Trigger that has no fields"} =
             GraphValidator.validate(nodes, [])
  end

  defp oban_running? do
    Oban.config(HeddleCore.Oban)
    true
  rescue
    _error -> false
  end
end
