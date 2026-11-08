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

  describe "the claude program" do
    setup do
      Application.put_env(:heddle_ai, :claude_binary, &Settings.claude_binary/0)
      on_exit(fn -> Application.put_env(:heddle_ai, :claude_binary, nil) end)
    end

    defp save_binary(view, path) do
      view |> form("#claude-binary-form", claude: %{path: path}) |> render_submit()
    end

    test "can be pointed at another path", %{conn: conn} do
      System.put_env("HEDDLE_CLAUDE_BIN", "/no/such/claude")
      view = open(conn)
      assert has_element?(view, "#claude-agent-binary", "Not found")

      save_binary(view, "/bin/true")

      assert Settings.claude_binary() == "/bin/true"
      assert has_element?(view, "#claude-agent-binary", "Found")
    end

    test "must be a program that exists", %{conn: conn} do
      view = open(conn)

      save_binary(view, "/no/such/claude")

      assert Settings.claude_binary() == nil
    end

    test "must be something that runs", %{conn: conn} do
      view = open(conn)

      save_binary(view, "/etc/hostname")

      assert Settings.claude_binary() == nil
    end

    test "goes back to being found when emptied", %{conn: conn} do
      {:ok, _setting} = Settings.set_claude_binary("/bin/true")
      view = open(conn)

      save_binary(view, "")

      assert Settings.claude_binary() == nil
    end
  end

  describe "Terminal" do
    setup do
      Application.put_env(:heddle_ui, :terminal, true)
      Application.put_env(:heddle_ui, :terminal_command, ["/bin/sh"])

      on_exit(fn ->
        Application.delete_env(:heddle_ui, :terminal)
        Application.delete_env(:heddle_ui, :terminal_command)
      end)
    end

    test "starts off, and is turned on here", %{conn: conn} do
      view = open(conn)
      assert has_element?(view, ~s(#terminal-toggle[aria-checked="false"]))

      view |> element("#terminal-toggle") |> render_click()

      assert has_element?(view, ~s(#terminal-toggle[aria-checked="true"]))
      assert Settings.terminal_enabled?()
    end

    test "can't be turned on where it isn't supported", %{conn: conn} do
      Application.put_env(:heddle_ui, :terminal, false)
      view = open(conn)

      assert has_element?(view, "#terminal-toggle[disabled]")
      assert has_element?(view, "#terminal-help")

      render_click(view, "toggle_terminal", %{})

      refute Settings.terminal_enabled?()
    end

    test "is what the Claude Agent points a subscription to", %{conn: conn} do
      System.put_env("HEDDLE_CLAUDE_BIN", "/bin/true")

      assert has_element?(open(conn), "#claude-agent-help", "turn on the Terminal below")
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
      assert has_element?(view, "#claude-agent-help", "set its path above")
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

  describe "model defaults" do
    alias HeddleCore.Credentials

    setup do
      {:ok, _credential} =
        Credentials.insert_credential(
          %{
            "name" => "gemini",
            "kind" => "ai",
            "values" => %{"provider" => "google", "api_key" => "k"}
          },
          nil
        )

      :ok
    end

    defp pick(view, params) do
      view |> form("#ai-defaults-form", ai: params) |> render_change()
    end

    test "offers the credentials and the models that fit", %{conn: conn} do
      view = open(conn)

      pick(view, %{"image_credential" => "gemini"})

      assert has_element?(view, "#ai_image_model option", "Default: Nano Banana 2.1")
      assert has_element?(view, "#ai_image_model option", "Nano Banana Pro")
      refute has_element?(view, "#ai_image_model option", "Gemini 3.8 Flash")
    end

    test "says when a provider can't do a task", %{conn: conn} do
      view = open(conn)

      pick(view, %{"speech_credential" => "gemini"})

      assert has_element?(view, "#ai-task-speech-problem")
      assert has_element?(view, "#ai_speech_model[disabled]")
    end

    test "forgets the model when the credential changes", %{conn: conn} do
      Settings.set_ai_defaults(%{
        "image" => %{"credential" => "gemini", "model" => "gemini-3-pro-image"}
      })

      view = open(conn)

      assert has_element?(view, "#ai_image_model option[selected]", "Nano Banana Pro")

      view
      |> element("#ai-defaults-form")
      |> render_change(%{
        "_target" => ["ai", "image_credential"],
        "ai" => %{"image_credential" => "", "image_model" => "gemini-3-pro-image"}
      })

      refute has_element?(view, "#ai_image_model option[selected]", "Nano Banana Pro")
    end

    test "saves what each task uses", %{conn: conn} do
      view = open(conn)

      pick(view, %{"image_credential" => "gemini"})

      view
      |> form("#ai-defaults-form", ai: %{"image_model" => "gemini-3-pro-image"})
      |> render_submit()

      assert %{"image" => %{"credential" => "gemini", "model" => "gemini-3-pro-image"}} =
               Settings.ai_defaults()
    end
  end
end
