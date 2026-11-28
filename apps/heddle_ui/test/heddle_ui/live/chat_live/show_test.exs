defmodule HeddleUI.ChatLive.ShowTest do
  # The node registry is global: one test at a time.
  use HeddleUI.ConnCase, async: false

  import Phoenix.LiveViewTest
  import HeddleCore.AccountsFixtures
  import HeddleCore.FlowsFixtures

  alias HeddleCore.Chats

  setup %{conn: conn} do
    on_exit(HeddleUI.FakeChatNode.register())
    user = user_fixture()
    workspace = workspace_fixture(user)

    flow =
      flow_fixture(
        user: user,
        workspace: workspace,
        nodes: [
          %{
            "id" => "talk",
            "type" => "Test: Talk",
            "label" => "Talk",
            "controls" => %{"name" => "Ana"}
          }
        ]
      )

    scope = user_scope_fixture(user)
    {:ok, chat} = Chats.link(scope, flow, "talk")
    %{conn: conn, user: user, flow: flow, scope: scope, chat: chat}
  end

  test "anyone with the link talks to the published trigger", %{conn: conn, chat: chat} do
    {:ok, lv, html} = live(conn, ~p"/c/#{chat.token}")
    assert html =~ "Ana"
    assert has_element?(lv, "#chat-empty")

    lv |> form("#chat-form", %{"message" => "hello"}) |> render_submit()

    assert has_element?(lv, "#chat-message-0", "hello")
    assert has_element?(lv, "#chat-message-1", "You said: hello")
  end

  test "what the package refuses shows as an alert", %{conn: conn, chat: chat} do
    {:ok, lv, _html} = live(conn, ~p"/c/#{chat.token}")
    lv |> form("#chat-form", %{"message" => "fail"}) |> render_submit()
    assert has_element?(lv, "#chat-alert", "It can't now.")
  end

  test "each browser is a conversation of its own", %{conn: conn, chat: chat} do
    {:ok, lv, _html} = live(conn, ~p"/c/#{chat.token}")
    lv |> form("#chat-form", %{"message" => "mine"}) |> render_submit()

    {:ok, other, _html} = live(build_conn(), ~p"/c/#{chat.token}")
    assert has_element?(other, "#chat-empty")
  end

  test "an unknown link shows that the chat isn't here", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/c/nope")
    assert has_element?(lv, "#chat-missing")
  end

  test "a new link replaces the old one", %{conn: conn, flow: flow, scope: scope, chat: chat} do
    {:ok, new} = Chats.regenerate(scope, flow, "talk")
    assert new.token != chat.token

    {:ok, lv, _html} = live(conn, ~p"/c/#{chat.token}")
    assert has_element?(lv, "#chat-missing")
  end

  test "someone who can run the flow tries it from the editor", %{
    conn: conn,
    user: user,
    flow: flow
  } do
    {:ok, lv, html} = conn |> log_in_user(user) |> live(~p"/flows/#{flow.id}/chat/talk")
    assert html =~ "chat-test-banner"

    lv |> form("#chat-form", %{"message" => "test"}) |> render_submit()
    assert has_element?(lv, "#chat-message-1", "You said: test")
  end

  test "a flow not published asks to publish it first", %{conn: conn, user: user, scope: scope} do
    draft =
      flow_fixture(
        user: user,
        published: false,
        nodes: [%{"id" => "talk", "type" => "Test: Talk", "label" => "Talk", "controls" => %{}}]
      )

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/flows/#{draft.id}/chat/talk")
    assert has_element?(lv, "#chat-missing", "Publish the flow")
    assert {:ok, _chat} = Chats.link(scope, draft, "talk")

    assert {:error, :not_found} =
             Chats.published(Chats.link(scope, draft, "talk") |> elem(1) |> Map.get(:token))
  end

  test "the editor's drawer shows the chat link and the package's panel", %{
    conn: conn,
    user: user,
    flow: flow
  } do
    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/flows/#{flow.id}")

    render_hook(lv, "open_node_config", %{
      "nodeId" => "talk",
      "nodeData" => %{
        "id" => "talk",
        "type" => "Test: Talk",
        "label" => "Talk",
        "controls" => %{"name" => %{"value" => "Ana", "type" => "text", "label" => "Name"}}
      }
    })

    assert lv |> element("#chat-link-url") |> render() =~ "/c/"
    assert has_element?(lv, "#chat-link-test")
    assert has_element?(lv, "#package-panel-0", "Instances")
    assert has_element?(lv, "#package-panel-0", "Ana")

    lv |> element("#package-panel-refresh") |> render_click()
    assert has_element?(lv, "#package-panel-0", "Ana")
  end
end
