defmodule HeddleUI.FlowLive.CodeFieldTest do
  use HeddleUI.ConnCase, async: true

  import Phoenix.LiveViewTest
  import HeddleCore.AccountsFixtures
  import HeddleCore.FlowsFixtures

  setup %{conn: conn} do
    user = user_fixture()
    workspace = workspace_fixture(user)

    flow =
      flow_fixture(
        user: user,
        workspace: workspace,
        nodes: [%{"id" => "http", "type" => "HTTP Request", "label" => "Call", "controls" => %{}}]
      )

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/flows/#{flow.id}")
    %{lv: lv}
  end

  defp open(lv, controls) do
    render_hook(lv, "open_node_config", %{
      "nodeId" => "http",
      "nodeData" => %{
        "id" => "http",
        "type" => "HTTP Request",
        "label" => "Call",
        "controls" => controls
      }
    })
  end

  test "a field of code opens in the editor with its language", %{lv: lv} do
    open(lv, %{
      "body" => %{
        "value" => ~s({"a": 1}),
        "type" => "textarea",
        "language" => "json",
        "label" => "Body"
      },
      "note" => %{"value" => "hi", "type" => "textarea", "label" => "Note"},
      "state" => %{"value" => %{"stage" => "new"}, "type" => "json", "label" => "State"}
    })

    assert has_element?(lv, ~s(#code-field-http-body[phx-hook="CodeField"][data-language="json"]))
    assert has_element?(lv, ~s(#code-field-http-body textarea[name="body"]), ~s({"a": 1}))
    assert has_element?(lv, ~s(#code-field-http-state[data-language="json"]))
    assert has_element?(lv, ~s(#code-field-http-state textarea), ~s("stage": "new"))
    refute has_element?(lv, "#code-field-http-note")
    assert has_element?(lv, ~s(textarea#node-field-note))
  end

  test "the definitions say which fields are code" do
    fields = HeddleNodes.Nodes.get_node("HTTP Request").ui_fields
    assert Enum.find(fields, &(&1.name == :body)).language == :json
    assert Enum.find(fields, &(&1.name == :headers)).language == :json
  end
end
