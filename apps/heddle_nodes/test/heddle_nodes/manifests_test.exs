defmodule HeddleNodes.ManifestsTest do
  use ExUnit.Case, async: false

  alias HeddleNodes.{Manifests, Nodes, Packages}

  defmodule Vault do
    def fetch(7, "bot", "slack"), do: {:ok, %{"token" => "xoxb"}}
    def fetch(_ws, name, _kind), do: {:error, "no #{name}"}
  end

  setup do
    previous = Application.get_env(:heddle_nodes, :credentials_client)
    Application.put_env(:heddle_nodes, :credentials_client, Vault)
    on_exit(fn -> Application.put_env(:heddle_nodes, :credentials_client, previous) end)
  end

  test "finds the nodes of the packages Heddle was built with" do
    names = Enum.map(Packages.definitions(), & &1.name)

    assert "Slack: Send Message" in names
    assert "Slack: Upload File" in names
    assert "SQL: Run Query" in names

    assert Nodes.get_node_module("Slack: Send Message") ==
             HeddleIntegrations.Slack.Slack.SendMessage

    assert %{category: :slack, outputs: ["success", "error"]} =
             Nodes.get_node("Slack: Send Message")
  end

  test "declares the credential kinds of the manifests the packages carry" do
    kinds = Map.new(Manifests.all_credential_kinds(), &{&1.id, &1})

    assert %{label: "Slack", fields: [%{name: "token", secret: true}]} = kinds["slack"]
  end

  test "a package's trigger polls with the credential of the flow's workspace" do
    assert %{manifest: manifest} =
             Enum.find(Manifests.poll_triggers(), &(&1.type == "Slack: New Message"))

    Req.Test.stub(HeddleNodes.Nodes.HttpRequest, fn conn ->
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer xoxb"]
      Req.Test.json(conn, %{"ok" => true, "messages" => [%{"ts" => "1", "text" => "a"}]})
    end)

    context = %{"workspace_id" => 7, "credential" => "bot", "channel" => "C1"}

    assert {:ok, [{"1", %{"text" => "a"}}]} = Manifests.poll(manifest, "New Message", context)
  end
end
