defmodule HeddleUI.AILive.IndexTest do
  # Not async: it sets the LLM variables for the whole VM.
  use HeddleUI.ConnCase, async: false

  import Phoenix.LiveViewTest
  import HeddleCore.AccountsFixtures

  alias HeddleCore.Settings

  @variables ~w(
    HEDDLE_LLM_PROVIDER HEDDLE_LLM_MODEL HEDDLE_LLM_API_KEY OPENAI_API_KEY OPENAI_MODEL
    HEDDLE_CLAUDE_BIN HEDDLE_CLAUDE_API_KEY
  )

  setup do
    previous = System.get_env() |> Map.take(@variables)
    Enum.each(@variables, &System.delete_env/1)

    on_exit(fn ->
      Enum.each(@variables, &System.delete_env/1)
      System.put_env(previous)
    end)
  end

  defp open(conn) do
    {:ok, view, _html} = conn |> log_in_user(system_admin_fixture()) |> live(~p"/ai")
    view
  end

  describe "access" do
    test "requires authentication", %{conn: conn} do
      assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/ai")
      assert path == ~p"/users/log-in"
    end

    test "sends a regular user back to the dashboard", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} =
               conn |> log_in_user(user_fixture()) |> live(~p"/ai")
    end
  end

  describe "LLM provider" do
    test "lists the variables when nothing is configured", %{conn: conn} do
      view = open(conn)

      assert has_element?(view, "#llm-status[data-state=not_configured]")
      assert has_element?(view, "#llm-variables li", "HEDDLE_LLM_PROVIDER")
      refute has_element?(view, "#llm-provider-name")
    end

    test "shows the provider and model, never the key", %{conn: conn} do
      System.put_env(%{
        "HEDDLE_LLM_PROVIDER" => "anthropic",
        "HEDDLE_LLM_MODEL" => "claude-sonnet-5-5",
        "HEDDLE_LLM_API_KEY" => "sk-ant-secret"
      })

      view = open(conn)

      assert has_element?(view, "#llm-status[data-state=ready]")
      assert has_element?(view, "#llm-provider-name", "anthropic")
      assert has_element?(view, "#llm-model", "claude-sonnet-5-5")
      refute render(view) =~ "sk-ant-secret"
    end

    test "names only what is missing", %{conn: conn} do
      System.put_env(%{"HEDDLE_LLM_PROVIDER" => "anthropic", "HEDDLE_LLM_MODEL" => "m"})

      view = open(conn)

      assert has_element?(view, "#llm-status[data-state=invalid]")
      assert has_element?(view, "#llm-variables li", "HEDDLE_LLM_API_KEY")
      refute has_element?(view, "#llm-variables li", "HEDDLE_LLM_MODEL")
    end

    test "flags the legacy OpenAI variables", %{conn: conn} do
      System.put_env("OPENAI_API_KEY", "sk-test")

      view = open(conn)

      assert has_element?(view, "#llm-provider-name", "openai")
      assert has_element?(view, "#llm-legacy-notice")
    end
  end

  describe "Claude Agent" do
    defp agent_ready do
      System.put_env(%{"HEDDLE_CLAUDE_BIN" => "/bin/true", "HEDDLE_CLAUDE_API_KEY" => "sk-ant"})
    end

    test "can't be turned on without the binary", %{conn: conn} do
      System.put_env("HEDDLE_CLAUDE_BIN", "/no/such/claude")

      view = open(conn)

      assert has_element?(view, "#claude-agent-toggle[disabled]")
      assert has_element?(view, "#claude-agent-help", "HEDDLE_CLAUDE_BIN")
    end

    test "asks for a key, and says subscriptions don't work", %{conn: conn} do
      System.put_env("HEDDLE_CLAUDE_BIN", "/bin/true")

      view = open(conn)

      assert has_element?(view, "#claude-agent-toggle[disabled]")
      assert has_element?(view, "#claude-agent-help", "HEDDLE_CLAUDE_API_KEY")
    end

    test "is saved for the whole instance", %{conn: conn} do
      agent_ready()
      view = open(conn)

      assert has_element?(view, "#claude-agent-toggle[aria-checked=false]")

      view |> element("#claude-agent-toggle") |> render_click()

      assert has_element?(view, "#claude-agent-toggle[aria-checked=true]")
      assert Settings.claude_agent_enabled?()

      view |> element("#claude-agent-toggle") |> render_click()

      refute Settings.claude_agent_enabled?()
    end

    test "refuses a forged event while unavailable", %{conn: conn} do
      System.put_env("HEDDLE_CLAUDE_BIN", "/no/such/claude")

      view = open(conn)
      render_click(view, "toggle_claude_agent")

      refute Settings.claude_agent_enabled?()
    end

    test "shows as off when it stops being available", %{conn: conn} do
      Settings.set_claude_agent_enabled(true)
      System.put_env("HEDDLE_CLAUDE_BIN", "/no/such/claude")

      assert has_element?(open(conn), "#claude-agent-toggle[aria-checked=false]")
    end

    test "never shows the key", %{conn: conn} do
      agent_ready()

      view = open(conn)

      assert has_element?(view, "#claude-agent-key")
      refute render(view) =~ "sk-ant"
    end
  end

  describe "MCP server" do
    test "shows how to connect an external agent", %{conn: conn} do
      view = open(conn)

      assert has_element?(view, "#mcp-command", "claude mcp add")
      assert has_element?(view, "#mcp-command", "/mcp")
      assert has_element?(view, "#mcp-api-keys-link[href='/api-keys']")
    end
  end

  describe "create with AI button on the flow list" do
    test "appears with an LLM configured", %{conn: conn} do
      System.put_env("OPENAI_API_KEY", "sk-test")

      {:ok, view, _html} = conn |> log_in_user(system_admin_fixture()) |> live(~p"/flows")

      assert has_element?(view, "#create-flow-with-ai[href='/flows/new/ai']")
    end

    test "is hidden without one", %{conn: conn} do
      {:ok, view, _html} = conn |> log_in_user(system_admin_fixture()) |> live(~p"/flows")

      refute has_element?(view, "#create-flow-with-ai")
    end
  end
end
