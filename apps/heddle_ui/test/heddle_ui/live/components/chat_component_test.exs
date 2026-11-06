defmodule HeddleUI.ChatComponentTest do
  use HeddleUI.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias HeddleUI.Components.ChatComponent

  @partial ~s({"action": "create_flow", "nodes": [)

  defp chat(messages, loading) do
    render_component(ChatComponent, id: "chat", open: true, messages: messages, loading: loading)
  end

  test "shows the flow being built while the reply comes in" do
    assert chat([{:user, "hi"}, {:ai, @partial}], true) =~ "Constructing flow..."
  end

  test "says so when a finished reply couldn't be applied" do
    html = chat([{:user, "hi"}, {:ai, @partial}], false)

    refute html =~ "Constructing flow..."
    assert html =~ "couldn&#39;t build this flow"
  end

  test "an old reply stops spinning when a new one is loading" do
    html = chat([{:user, "hi"}, {:ai, @partial}, {:user, "?"}, {:ai, "Sure"}], true)

    refute html =~ "Constructing flow..."
    assert html =~ "couldn&#39;t build this flow"
  end

  test "shows plain replies as they are" do
    assert chat([{:user, "hi"}, {:ai, "Hello"}], false) =~ "Hello"
  end
end
