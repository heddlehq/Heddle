defmodule HeddleUI.PublicAPI.V1.LiveControllerTest do
  # Not async: the session of a flow is shared by everyone who edits it.
  use HeddleUI.ConnCase, async: false

  import HeddleCore.AccountsFixtures
  import HeddleCore.FlowsFixtures

  alias HeddleCore.Accounts.Scope
  alias HeddleCore.Flows
  alias HeddleCore.Flows.Session
  alias HeddleUI.FlowPresence
  alias HeddleUI.PublicAPI.V1.LiveFlow

  @start %{
    "id" => "1",
    "type" => "Start",
    "label" => "Start",
    "controls" => %{},
    "position" => %{"x" => 0, "y" => 0}
  }
  @output %{
    "id" => "2",
    "type" => "Output",
    "label" => "Output",
    "controls" => %{},
    "position" => %{"x" => 200, "y" => 0}
  }

  setup do
    user = user_fixture()
    flow = flow_fixture(%{user: user, nodes: [@start]})

    on_exit(fn ->
      case Session.whereis(flow.id) do
        nil -> :ok
        pid -> Horde.DynamicSupervisor.terminate_child(Session.supervisor(), pid)
      end
    end)

    %{user: user, flow: flow, scope: Scope.for_user(user)}
  end

  defp viewer(flow) do
    viewer = user_fixture()
    member_fixture(HeddleCore.Workspaces.get_workspace(flow.workspace_id), viewer, "viewer")
    HeddleCore.Repo.reload!(viewer)
  end

  defp authorize(conn, user, scopes) do
    {:ok, %{token: token}} = create_api_key(user, %{name: "test key", scopes: scopes})
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  defp graph(nodes), do: %{"nodes" => nodes, "connections" => [], "comments" => []}

  # Splits what `LiveFlow` writes back into `{name, data}`.
  defp decode(events) do
    for event <- events do
      ["event: " <> name, "data: " <> data] = event |> String.trim() |> String.split("\n")
      {name, Jason.decode!(data)}
    end
  end

  describe "changes" do
    test "applies only what the client changed since its base, keeping what others did", %{
      conn: conn,
      user: user,
      flow: flow
    } do
      # Someone else adds a node the client hasn't seen.
      other = viewer(flow)
      member = HeddleCore.Repo.get_by!(HeddleCore.Workspaces.Member, user_id: other.id)
      HeddleCore.Repo.update!(Ecto.Changeset.change(member, role: "editor"))

      assert {:ok, 1} =
               Flows.apply_operations(Scope.for_user(other), flow.id, [
                 %{"op" => "add_node", "node" => @output}
               ])

      renamed = Map.put(@start, "label", "Begin")

      conn =
        conn
        |> authorize(user, ["workflows:write"])
        |> post(~p"/api/v1/workflows/#{flow.id}/changes", %{
          base: graph([@start]),
          graph: graph([renamed]),
          client: "treadle-1"
        })

      assert %{"data" => %{"seq" => 2, "applied" => 2, "graph" => graph}} =
               json_response(conn, 200)

      assert [%{"id" => "1", "label" => "Begin"}, %{"id" => "2"}] = graph["nodes"]

      assert [%{"label" => "Begin"}, %{"id" => "2"}] =
               Flows.get_flow(Scope.for_user(user), flow.id).nodes
    end

    test "applies operations", %{conn: conn, user: user, flow: flow} do
      :ok = Session.subscribe(flow.id)

      conn =
        conn
        |> authorize(user, ["workflows:write"])
        |> post(~p"/api/v1/workflows/#{flow.id}/changes", %{
          ops: [%{"op" => "add_node", "node" => @output}],
          client: "treadle-1",
          ref: 7
        })

      assert %{"data" => %{"applied" => 1, "graph" => %{"nodes" => [_, %{"id" => "2"}]}}} =
               json_response(conn, 200)

      assert_receive {:flow_ops, %{seq: 1, client: "treadle-1", ref: 7}}
    end

    test "nothing to change gives the draft as it is", %{conn: conn, user: user, flow: flow} do
      conn =
        conn
        |> authorize(user, ["workflows:write"])
        |> post(~p"/api/v1/workflows/#{flow.id}/changes", %{
          base: graph([@start]),
          graph: graph([@start])
        })

      assert %{"data" => %{"seq" => 0, "applied" => nil, "graph" => %{"nodes" => [_]}}} =
               json_response(conn, 200)
    end

    test "operations that no longer apply are refused", %{conn: conn, user: user, flow: flow} do
      conn =
        conn
        |> authorize(user, ["workflows:write"])
        |> post(~p"/api/v1/workflows/#{flow.id}/changes", %{
          ops: [%{"op" => "remove_node", "id" => "gone"}]
        })

      assert %{"error" => %{"code" => "conflict"}} = json_response(conn, 409)
    end

    test "something that isn't a change is refused", %{conn: conn, user: user, flow: flow} do
      for body <- [%{}, %{ops: "no"}, %{base: graph([@start]), graph: %{"nodes" => ["x"]}}] do
        conn =
          conn
          |> authorize(user, ["workflows:write"])
          |> post(~p"/api/v1/workflows/#{flow.id}/changes", body)

        assert %{"error" => %{"code" => "invalid_request"}} = json_response(conn, 422)
      end
    end

    test "a viewer may not change it", %{conn: conn, flow: flow} do
      conn =
        conn
        |> authorize(viewer(flow), ["workflows:write"])
        |> post(~p"/api/v1/workflows/#{flow.id}/changes", %{
          ops: [%{"op" => "add_node", "node" => @output}]
        })

      assert %{"error" => %{"code" => "forbidden"}} = json_response(conn, 403)
    end

    test "a key that only reads may not change it", %{conn: conn, user: user, flow: flow} do
      conn =
        conn
        |> authorize(user, ["workflows:read"])
        |> post(~p"/api/v1/workflows/#{flow.id}/changes", %{ops: []})

      assert json_response(conn, 403)
    end

    test "a workflow of another workspace looks missing", %{conn: conn, flow: flow} do
      conn =
        conn
        |> authorize(user_fixture(), ["workflows:write"])
        |> post(~p"/api/v1/workflows/#{flow.id}/changes", %{ops: []})

      assert json_response(conn, 404)
    end
  end

  describe "focus" do
    test "points the person's stream at nodes, for everyone to see", %{
      conn: conn,
      user: user,
      flow: flow,
      scope: scope
    } do
      {:ok, state, _events} = LiveFlow.start(scope, flow.id)

      conn =
        conn
        |> authorize(user, ["workflows:read"])
        |> post(~p"/api/v1/workflows/#{flow.id}/focus", %{
          client: state.client,
          selected: ["1", 2],
          editing: "1"
        })

      assert response(conn, 204)
      assert_receive {:live_focus, ["1"], "1"} = message
      {:ok, [], _state} = LiveFlow.handle(message, state)

      assert %{metas: [%{selected: ["1"], editing: "1"}]} =
               FlowPresence.get_by_key(FlowPresence.topic(flow.id), state.client)
    end

    test "only reaches a stream of the same person", %{conn: conn, flow: flow, scope: scope} do
      {:ok, state, _events} = LiveFlow.start(scope, flow.id)
      other = viewer(flow)

      for {who, client} <- [{other, state.client}, {Scope.for_user(other).user, "unknown"}] do
        conn =
          conn
          |> authorize(who, ["workflows:read"])
          |> post(~p"/api/v1/workflows/#{flow.id}/focus", %{client: client, selected: []})

        assert json_response(conn, 404)
      end
    end
  end

  describe "live" do
    test "streams the flow as server-sent events, until it is gone", %{
      conn: conn,
      user: user,
      flow: flow,
      scope: scope
    } do
      :ok = Phoenix.PubSub.subscribe(HeddleCore.PubSub, FlowPresence.topic(flow.id))
      conn = authorize(conn, user, ["workflows:read"])

      stream = Task.async(fn -> get(conn, ~p"/api/v1/workflows/#{flow.id}/live") end)

      # It is on the flow once it shows among who is there.
      assert_receive %Phoenix.Socket.Broadcast{event: "presence_diff"}, 2000
      {:ok, _flow} = Flows.delete_flow(scope, flow)
      send(stream.pid, {:flow_ops, %{flow_id: flow.id, epoch: nil, seq: 99, ops: []}})

      conn = Task.await(stream)
      assert conn.status == 200
      assert ["text/event-stream" <> _] = get_resp_header(conn, "content-type")
      assert conn.resp_body =~ "event: ready\n"
      assert conn.resp_body =~ "event: presence\n"
      assert [] = FlowPresence.list(FlowPresence.topic(flow.id)) |> Map.to_list()
    end

    test "a workflow of another workspace looks missing", %{conn: conn, flow: flow} do
      conn =
        conn
        |> authorize(user_fixture(), ["workflows:read"])
        |> get(~p"/api/v1/workflows/#{flow.id}/live")

      assert json_response(conn, 404)
    end
  end

  describe "the live stream" do
    test "starts with the draft, and who is there", %{flow: flow, scope: scope, user: user} do
      {:ok, state, events} = LiveFlow.start(scope, flow.id)

      assert [{"ready", ready}, {"presence", %{"people" => people}}] = decode(events)

      assert %{
               "client" => client,
               "can_edit" => true,
               "user_id" => user_id,
               "seq" => 0,
               "graph" => %{"nodes" => [%{"id" => "1"}], "connections" => [], "comments" => []}
             } = ready

      assert client == state.client
      assert user_id == user.id
      assert [%{"client" => ^client, "kind" => "person", "user_id" => ^user_id}] = people
    end

    test "can't edit for a viewer, or with a key that only reads", %{flow: flow, scope: scope} do
      {:ok, %{can_edit: false}, _events} = LiveFlow.start(Scope.for_user(viewer(flow)), flow.id)
      {:ok, %{can_edit: false}, _events} = LiveFlow.start(scope, flow.id, can_write: false)
    end

    test "a workflow of another workspace looks missing", %{flow: flow} do
      assert {:error, :not_found} = LiveFlow.start(Scope.for_user(user_fixture()), flow.id)
    end

    test "tells each change with the graph after it", %{flow: flow, scope: scope} do
      {:ok, state, _events} = LiveFlow.start(scope, flow.id)

      {:ok, 1} =
        Flows.apply_operations(scope, flow.id, [%{"op" => "add_node", "node" => @output}], %{
          client: "web"
        })

      assert_receive {:flow_ops, %{seq: 1}} = message
      assert {:ok, events, %{seq: 1}} = LiveFlow.handle(message, state)

      assert [{"change", %{"seq" => 1, "client" => "web", "ops" => [_], "graph" => graph}}] =
               decode(events)

      assert [%{"id" => "1"}, %{"id" => "2"}] = graph["nodes"]
    end

    test "starts over when it missed a change", %{flow: flow, scope: scope} do
      {:ok, state, _events} = LiveFlow.start(scope, flow.id)

      gap = {:flow_ops, %{flow_id: flow.id, epoch: state.epoch, seq: 5, ops: []}}

      assert {:ok, events, _state} = LiveFlow.handle(gap, state)
      assert [{"ready", %{"client" => client}}] = decode(events)
      assert client == state.client
    end

    test "tells who comes and goes", %{flow: flow, scope: scope, user: user} do
      {:ok, state, _events} = LiveFlow.start(scope, flow.id)
      topic = FlowPresence.topic(flow.id)
      assert_receive %Phoenix.Socket.Broadcast{event: "presence_diff"}

      someone = spawn(fn -> Process.sleep(:infinity) end)
      {:ok, _ref} = FlowPresence.track(someone, topic, "web-1", FlowPresence.person(user))
      assert_receive %Phoenix.Socket.Broadcast{event: "presence_diff"} = diff

      assert {:ok, events, _state} = LiveFlow.handle(diff, state)
      assert [{"presence", %{"people" => people}}] = decode(events)

      assert people |> Enum.map(& &1["client"]) |> Enum.sort() ==
               Enum.sort(["web-1", state.client])
    end

    test "passes on where canvas pointers are, a few times a second", %{
      flow: flow,
      scope: scope
    } do
      {:ok, state, _events} = LiveFlow.start(scope, flow.id)
      topic = FlowPresence.topic(flow.id)

      cursor = fn x ->
        %Phoenix.Socket.Broadcast{
          topic: topic,
          event: "cursor",
          payload: %{client: "web-1", x: x, y: 2}
        }
      end

      {:ok, [], state} = LiveFlow.handle(cursor.(1), state)
      {:ok, [], state} = LiveFlow.handle(cursor.(9), state)

      assert_receive :live_cursors
      assert {:ok, events, _state} = LiveFlow.handle(:live_cursors, state)
      assert [{"cursor", %{"client" => "web-1", "x" => 9, "y" => 2}}] = decode(events)
    end

    test "leaves the flow when it stops", %{flow: flow, scope: scope} do
      {:ok, state, _events} = LiveFlow.start(scope, flow.id)

      LiveFlow.stop(state)

      assert [] = FlowPresence.get_by_key(FlowPresence.topic(flow.id), state.client)
    end
  end
end
