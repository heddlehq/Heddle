defmodule HeddleCore.Flows.VersionsTest do
  use HeddleCore.DataCase

  import HeddleCore.AccountsFixtures
  import HeddleCore.FlowsFixtures

  alias HeddleCore.Accounts.Scope
  alias HeddleCore.Executions
  alias HeddleCore.Flows
  alias HeddleCore.Flows.{Version, Versions}

  @start %{"id" => "1", "type" => "Start", "controls" => %{}, "position" => %{"x" => 0, "y" => 0}}
  @output %{
    "id" => "2",
    "type" => "Output",
    "controls" => %{},
    "position" => %{"x" => 200, "y" => 0}
  }

  defmodule Manifest do
    def get_definitions do
      [
        %{name: "Start", inputs: [], outputs: ["exec"]},
        %{name: "Output", inputs: ["exec"], outputs: []}
      ]
    end
  end

  setup do
    previous = Application.get_env(:heddle_core, :graph_manifest)
    Application.put_env(:heddle_core, :graph_manifest, Manifest)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:heddle_core, :graph_manifest, previous),
        else: Application.delete_env(:heddle_core, :graph_manifest)
    end)

    user = user_fixture()
    workspace = workspace_fixture(user)
    scope = Scope.for_user(Repo.reload!(user))
    flow = flow_fixture(%{user: user, workspace: workspace, published: false, nodes: [@start]})

    %{user: user, workspace: workspace, scope: scope, flow: flow}
  end

  defp scope_as(workspace, role) do
    user = user_fixture()
    member_fixture(workspace, user, role)
    Scope.for_user(Repo.reload!(user))
  end

  describe "publish/3" do
    test "makes the draft what production runs", %{scope: scope, flow: flow, user: user} do
      refute Versions.published?(flow)
      assert Versions.unpublished_changes?(flow)

      assert {:ok, %Version{} = version} = Versions.publish(scope, flow, %{"note" => " First "})

      flow = Flows.get_flow!(flow.id)
      assert flow.published_version_id == version.id
      assert version.number == 1
      assert version.kind == "publish"
      assert version.note == "First"
      assert version.author_id == user.id
      assert version.nodes == flow.nodes
      refute Versions.unpublished_changes?(flow)
      assert Versions.published_flow(flow).nodes == flow.nodes
    end

    test "says who changed the draft since the version before", %{
      scope: scope,
      flow: flow,
      workspace: workspace
    } do
      {:ok, _first} = Versions.publish(scope, flow)
      editor = scope_as(workspace, "editor")
      {:ok, flow} = Flows.update_flow(editor, flow, %{nodes: [@start, @output]})
      {:ok, flow} = Flows.update_flow(scope, flow, %{nodes: [@output]})
      # A save that changes nothing of the graph isn't a change.
      {:ok, flow} = Flows.update_flow(scope, flow, %{name: "Renamed"})

      assert flow.draft_contributor_ids == [editor.user.id, scope.user.id]

      {:ok, version} = Versions.publish(scope, flow)

      assert version.number == 2
      assert version.contributor_ids == [editor.user.id, scope.user.id]
      assert Flows.get_flow!(flow.id).draft_contributor_ids == []
    end

    test "an editor may publish, and an operator or a viewer may not", %{
      flow: flow,
      workspace: workspace
    } do
      assert {:ok, _version} = Versions.publish(scope_as(workspace, "editor"), flow)
      assert {:error, :forbidden} = Versions.publish(scope_as(workspace, "operator"), flow)
      assert {:error, :forbidden} = Versions.publish(scope_as(workspace, "viewer"), flow)
    end

    test "a flow of another workspace looks missing", %{flow: flow} do
      outsider = user_scope_fixture()

      assert {:error, :not_found} = Versions.publish(outsider, flow)
      assert {:error, :not_found} = Versions.list_versions(outsider, flow)
      assert Versions.get_version(outsider, flow, flow.id) == nil
    end
  end

  describe "list_versions/2" do
    test "lists the newest first, with what each changed", %{
      scope: scope,
      flow: flow,
      workspace: workspace
    } do
      {:ok, first} = Versions.publish(scope, flow)
      {:ok, flow} = Flows.update_flow(scope, flow, %{nodes: [@start, @output]})
      {:ok, second} = Versions.publish(scope, flow)

      viewer = scope_as(workspace, "viewer")
      assert {:ok, [newest, oldest]} = Versions.list_versions(viewer, flow)

      assert newest.version.id == second.id
      assert Enum.map(newest.diff.nodes.added, & &1["id"]) == ["2"]
      assert [%{id: id}] = newest.contributors
      assert id == scope.user.id
      assert oldest.version.id == first.id
      assert Enum.map(oldest.diff.nodes.added, & &1["id"]) == ["1"]
    end
  end

  describe "publish_version/4" do
    test "puts an older version back in production, leaving the draft", %{
      scope: scope,
      flow: flow
    } do
      {:ok, first} = Versions.publish(scope, flow)
      {:ok, flow} = Flows.update_flow(scope, flow, %{nodes: [@start, @output]})
      {:ok, _second} = Versions.publish(scope, flow)

      assert {:ok, again} = Versions.publish_version(scope, flow, first.id, %{"note" => "Broke"})

      flow = Flows.get_flow!(flow.id)
      assert flow.published_version_id == again.id
      assert again.number == 3
      assert again.source_version_id == first.id
      assert again.source.number == 1
      assert again.nodes == first.nodes
      assert flow.nodes == [@start, @output]
      assert Versions.unpublished_changes?(flow)
    end

    test "only takes a version of the same flow", %{
      scope: scope,
      flow: flow,
      user: user,
      workspace: workspace
    } do
      other = flow_fixture(%{user: user, workspace: workspace})

      assert {:error, :not_found} =
               Versions.publish_version(scope, flow, other.published_version_id)
    end
  end

  describe "restore/3" do
    test "replaces the draft, keeping what it had", %{scope: scope, flow: flow} do
      {:ok, first} = Versions.publish(scope, flow)
      {:ok, flow} = Flows.update_flow(scope, flow, %{nodes: [@start, @output]})

      assert {:ok, flow} = Versions.restore(scope, flow, first.id)

      assert flow.nodes == first.nodes
      assert %Version{kind: "checkpoint", nodes: [@start, @output]} = Versions.latest(flow)
      # What production runs doesn't change.
      assert flow.published_version_id == first.id
    end

    test "a viewer may not restore", %{scope: scope, flow: flow, workspace: workspace} do
      {:ok, first} = Versions.publish(scope, flow)

      assert {:error, :forbidden} =
               Versions.restore(scope_as(workspace, "viewer"), flow, first.id)
    end
  end

  describe "freeze_draft/2" do
    test "takes the newest version when the draft didn't change", %{scope: scope, flow: flow} do
      {:ok, published} = Versions.publish(scope, flow)

      assert {:ok, %Version{id: id}} = Versions.freeze_draft(Flows.get_flow!(flow.id))
      assert id == published.id
    end

    test "keeps a changed draft as a run version", %{scope: scope, flow: flow} do
      {:ok, _published} = Versions.publish(scope, flow)
      {:ok, flow} = Flows.update_flow(scope, flow, %{nodes: [@start, @output]})

      assert {:ok, %Version{kind: "run", number: 2} = version} =
               Versions.freeze_draft(flow, scope.user.id)

      assert version.nodes == [@start, @output]
      assert {:ok, %Version{id: id}} = Versions.freeze_draft(Flows.get_flow!(flow.id))
      assert id == version.id
    end
  end

  describe "checkpoints" do
    test "the draft is kept once the newest version is old enough", %{scope: scope, flow: flow} do
      {:ok, published} = Versions.publish(scope, flow)
      {:ok, flow} = Flows.update_flow(scope, flow, %{nodes: [@start, @output]})

      # Saved right after publishing, it isn't kept on its own yet.
      assert Versions.latest(flow).id == published.id

      later = DateTime.add(DateTime.utc_now(), Versions.checkpoint_every_minutes(), :minute)
      assert {:ok, %Version{kind: "checkpoint"}} = Versions.checkpoint_if_due(flow, nil, later)
    end

    test "the first change of a flow is kept right away", %{scope: scope, flow: flow} do
      assert Versions.latest(flow) == nil

      {:ok, flow} = Flows.update_flow(scope, flow, %{nodes: [@start, @output]})

      assert %Version{kind: "checkpoint", number: 1, contributor_ids: [id]} =
               Versions.latest(flow)

      assert id == scope.user.id
    end

    test "an empty flow with nothing kept keeps nothing", %{user: user, workspace: workspace} do
      flow = flow_fixture(%{user: user, workspace: workspace, published: false})

      assert {:ok, nil} = Versions.checkpoint(flow)
    end
  end

  describe "list_published_with_node/1" do
    test "finds flows by what they publish, with that graph", %{scope: scope, flow: flow} do
      assert Versions.list_published_with_node("Start") |> Enum.filter(&(&1.id == flow.id)) == []

      {:ok, _version} = Versions.publish(scope, flow)
      {:ok, _flow} = Flows.update_flow(scope, flow, %{nodes: [@output]})

      assert [found] =
               Versions.list_published_with_node("Start") |> Enum.filter(&(&1.id == flow.id))

      assert found.nodes == [@start]
      assert Versions.list_published_with_node("Output") |> Enum.filter(&(&1.id == flow.id)) == []
    end
  end

  describe "prune/1" do
    test "deletes old checkpoints nothing needs", %{scope: scope, flow: flow} do
      {:ok, flow} = Flows.update_flow(scope, flow, %{nodes: [@start, @output]})
      {:ok, old} = Versions.checkpoint(flow)
      {:ok, flow} = Flows.update_flow(scope, flow, %{nodes: [@output]})
      {:ok, used} = Versions.freeze_draft(flow)

      {:ok, _execution} =
        Executions.create_execution(%{flow_id: flow.id, flow_version_id: used.id})

      {:ok, flow} = Flows.update_flow(scope, flow, %{nodes: [@start]})
      {:ok, newest} = Versions.checkpoint(flow)

      assert Versions.prune(DateTime.add(DateTime.utc_now(), 31, :day)) == 1

      ids = Repo.all(from v in Version, where: v.flow_id == ^flow.id, select: v.id)
      refute old.id in ids
      assert used.id in ids
      assert newest.id in ids
    end

    test "keeps what is recent or published", %{scope: scope, flow: flow} do
      {:ok, _published} = Versions.publish(scope, flow)
      {:ok, flow} = Flows.update_flow(scope, flow, %{nodes: [@output]})
      {:ok, _checkpoint} = Versions.checkpoint(flow)

      assert Versions.prune() == 0
      assert Versions.prune(DateTime.add(DateTime.utc_now(), 31, :day)) == 0
    end
  end

  describe "what a run takes" do
    setup do
      unless Oban.whereis(HeddleCore.Oban) do
        start_supervised!({Oban, name: HeddleCore.Oban, repo: Repo, testing: :manual})
      end

      :ok
    end

    test "production can't run a flow that isn't published", %{flow: flow, scope: scope} do
      assert {:error, :not_published} = Executions.start_execution(flow, %{})
      assert {:error, :not_published} = Executions.run(scope, flow, %{})
    end

    test "production runs the published version", %{scope: scope, flow: flow} do
      {:ok, published} = Versions.publish(scope, flow)
      {:ok, flow} = Flows.update_flow(scope, Flows.get_flow!(flow.id), %{nodes: [@output]})

      assert {:ok, execution} = Executions.start_execution(flow, %{})
      assert execution.flow_version_id == published.id
      assert Versions.for_execution(flow, execution).nodes == [@start]
    end

    test "the editor runs the draft, frozen as it was", %{scope: scope, flow: flow} do
      assert {:ok, execution} = Executions.run(scope, flow, %{}, version: :draft)

      version = Repo.get!(Version, execution.flow_version_id)
      assert version.kind == "run"
      assert version.author_id == scope.user.id

      {:ok, flow} = Flows.update_flow(scope, flow, %{nodes: [@output]})
      assert Versions.for_execution(flow, execution).nodes == [@start]
    end

    test "saving and running runs what was saved", %{scope: scope, flow: flow} do
      assert {:ok, %{execution: execution}} =
               Executions.save_and_run(scope, flow, %{nodes: [@start, @output]})

      assert Repo.get!(Version, execution.flow_version_id).nodes == [@start, @output]
    end
  end

  describe "deleting a flow" do
    test "takes its versions with it", %{scope: scope, flow: flow} do
      {:ok, _version} = Versions.publish(scope, flow)

      assert {:ok, _flow} = Flows.delete_flow(scope, Flows.get_flow!(flow.id))
      assert Repo.all(from v in Version, where: v.flow_id == ^flow.id) == []
    end
  end
end
