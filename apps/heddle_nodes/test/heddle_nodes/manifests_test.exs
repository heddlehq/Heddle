defmodule HeddleNodes.ManifestsTest do
  use ExUnit.Case, async: false

  alias HeddleNodes.Manifests

  test "turns each action of a manifest into a node module" do
    assert Manifests.modules("slack") == [
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
end
