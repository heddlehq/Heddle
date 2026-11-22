defmodule HeddleNodes.ManifestsTest do
  use ExUnit.Case, async: false

  alias HeddleNodes.Manifests

  test "turns each action of a manifest into a node module" do
    assert Manifests.modules("slack") == [
             Manifests.Slack.NewMessage,
             Manifests.Slack.SendMessage,
             Manifests.Slack.ReadMessages,
             Manifests.Slack.UpdateMessage,
             Manifests.Slack.DeleteMessage,
             Manifests.Slack.AddReaction,
             Manifests.Slack.ListChannels
           ]

    definition = Manifests.Slack.ListChannels.definition()

    assert definition.name == "Slack: List Channels"
    assert definition.category == :slack
    assert definition.icon == "logo-slack"
    assert definition.outputs == ["success", "error"]

    assert [
             %{type: :credential, kind: "slack"},
             %{type: :select, name: :types, default: "public_channel", options: [_, _, _]}
           ] = definition.ui_fields
  end

  test "a number field shows as text, with its default" do
    fields = Manifests.Slack.ReadMessages.definition().ui_fields

    assert %{type: :text, default: "20"} = Enum.find(fields, &(&1[:name] == :limit))
  end

  test "declares the credential kinds of its manifests" do
    kinds = Map.new(Manifests.credential_kinds(), &{&1.id, &1})

    assert %{label: "Slack", fields: [%{name: "token", secret: true}]} = kinds["slack"]
    refute Map.has_key?(kinds["slack"], :oauth2)

    assert %{oauth2: %{token_url: "https://api.notion.com/v1/oauth/token"}} = kinds["notion"]
  end

  defmodule Vault do
    def fetch(_ws, "docs", "notion"), do: {:ok, %{"access_token" => "old"}}

    def fetch(_ws, "docs", "notion", refresh: true) do
      send(self(), :renewed)
      {:ok, %{"access_token" => "new"}}
    end
  end

  test "a Notion node renews its token once when Notion refuses it" do
    previous = Application.get_env(:heddle_nodes, :credentials_client)
    Application.put_env(:heddle_nodes, :credentials_client, Vault)
    on_exit(fn -> Application.put_env(:heddle_nodes, :credentials_client, previous) end)

    Req.Test.stub(HeddleNodes.Nodes.HttpRequest, fn conn ->
      case Plug.Conn.get_req_header(conn, "authorization") do
        ["Bearer old"] ->
          Plug.Conn.send_resp(conn, 401, "")

        ["Bearer new"] ->
          assert Plug.Conn.get_req_header(conn, "notion-version") == ["2022-06-28"]
          Req.Test.json(conn, %{"results" => [%{"id" => "p1", "url" => "u", "x" => 1}]})
      end
    end)

    context = %{"credential" => "docs", "query" => "Roadmap", "object" => "page"}

    assert {:ok, %{"result" => [%{"id" => "p1", "url" => "u"}]}, "success"} =
             Manifests.Notion.Search.handler(context, nil)

    assert_received :renewed
  end

  describe "triggers" do
    defmodule SlackVault do
      def fetch(7, "bot", "slack"), do: {:ok, %{"token" => "xoxb"}}
    end

    setup do
      previous = Application.get_env(:heddle_nodes, :credentials_client)
      Application.put_env(:heddle_nodes, :credentials_client, SlackVault)
      on_exit(fn -> Application.put_env(:heddle_nodes, :credentials_client, previous) end)
    end

    defp history(messages) do
      Req.Test.stub(HeddleNodes.Nodes.HttpRequest, fn conn ->
        assert conn.request_path == "/api/conversations.history"
        assert conn.query_params["channel"] == "C1"
        assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer xoxb"]
        Req.Test.json(conn, %{"ok" => true, "messages" => messages})
      end)
    end

    test "a trigger is a node a flow starts from, in its integration" do
      definition = Manifests.Slack.NewMessage.definition()

      assert definition.name == "Slack: New Message"
      assert definition.inputs == []
      assert definition.outputs == [:exec]
      assert definition.integration == "slack"
      assert definition.poll == %{trigger: "New Message", every: 1}
      assert [%{type: :credential, kind: "slack"}, %{name: :channel}] = definition.ui_fields

      assert %{type: "Slack: New Message"} =
               Enum.find(Manifests.poll_triggers(), &(&1.type == "Slack: New Message"))
    end

    test "polls the service and pairs each item with its id" do
      history([%{"ts" => "2", "text" => "b"}, %{"ts" => "1", "text" => "a"}])
      context = %{"workspace_id" => 7, "credential" => "bot", "channel" => "C1"}

      assert {:ok, [{"2", %{"text" => "b"}}, {"1", %{"text" => "a"}}]} =
               Manifests.poll(Manifests.get("slack"), "New Message", context)
    end

    test "passes on the item that started the run" do
      context = %{"item" => %{"ts" => "1", "text" => "hi"}}

      assert {:ok, %{"result" => %{"text" => "hi"}}, :exec} =
               Manifests.Slack.NewMessage.handler(context, nil)
    end

    test "run from the editor, takes the newest item the service has" do
      history([%{"ts" => "2", "text" => "newest"}, %{"ts" => "1", "text" => "a"}])
      context = %{"workspace_id" => 7, "credential" => "bot", "channel" => "C1"}

      assert {:ok, %{"result" => %{"text" => "newest"}}, :exec} =
               Manifests.Slack.NewMessage.handler(context, nil)

      history([])

      assert {:error, "Slack has nothing for New Message yet."} =
               Manifests.Slack.NewMessage.handler(context, nil)
    end
  end
end
