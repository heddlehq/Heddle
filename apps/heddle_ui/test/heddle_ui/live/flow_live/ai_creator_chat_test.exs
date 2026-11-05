defmodule HeddleUI.FlowLive.AICreatorChatTest do
  # Not async: it sets the planner and the OpenAI key for the whole VM.
  use HeddleUI.ConnCase, async: false

  import Phoenix.LiveViewTest
  import HeddleCore.AccountsFixtures

  alias HeddleCore.Accounts.Scope
  alias HeddleCore.Flows

  setup %{conn: conn} do
    previous_key = System.get_env("OPENAI_API_KEY")
    System.put_env("OPENAI_API_KEY", "test-key")
    Application.put_env(:heddle_ui, :flow_planner, HeddleUI.FakeFlowPlanner)

    on_exit(fn ->
      Application.delete_env(:heddle_ui, :flow_planner)

      if previous_key,
        do: System.put_env("OPENAI_API_KEY", previous_key),
        else: System.delete_env("OPENAI_API_KEY")
    end)

    admin = system_admin_fixture()
    {:ok, view, _html} = conn |> log_in_user(admin) |> live(~p"/flows/new/ai")

    %{admin: admin, view: view}
  end

  defp ask(view, content) do
    view |> element("form[phx-submit=send_message]") |> render_submit(%{content: content})
    render_async(view)
  end

  test "hides the plan marker from the conversation", %{view: view} do
    html = ask(view, "log my webhooks")

    assert html =~ "Add a Logger node"
    refute html =~ "PLAN_PROPOSED"
  end

  test "keeps the plan as separate lines", %{view: view} do
    ask(view, "log my webhooks")

    assert has_element?(view, "p.whitespace-pre-wrap", "Add a Webhook node")
  end

  test "offers to approve a proposed plan", %{view: view} do
    refute has_element?(view, "#ai-plan-approval")

    ask(view, "log my webhooks")

    assert has_element?(view, "#ai-approve-plan")
  end

  test "approving the plan creates the flow and opens it", %{admin: admin, view: view} do
    ask(view, "log my webhooks")

    view |> element("#ai-approve-plan") |> render_click()
    {path, _flash} = assert_redirect(view)

    assert [flow] = Flows.list_flows(Scope.for_user(admin))
    assert flow.name == "Planned Flow"
    assert path == ~p"/flows/#{flow.id}"
  end

  test "hides the JSON of a flow that could not be saved", %{admin: admin, view: view} do
    html = ask(view, "invalid")

    refute html =~ "create_flow"
    assert Flows.list_flows(Scope.for_user(admin)) == []
  end

  test "a reply without a plan withdraws the approval", %{view: view} do
    ask(view, "log my webhooks")
    ask(view, "hello")

    refute has_element?(view, "#ai-plan-approval")
  end
end
