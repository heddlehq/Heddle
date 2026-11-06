defmodule HeddleAI.ClaudeAgentTest do
  use ExUnit.Case, async: true

  alias HeddleAI.ClaudeAgent

  @bin "/bin/sh"

  describe "status/1" do
    test "is ready with a binary and a key" do
      env = %{"HEDDLE_CLAUDE_BIN" => @bin, "HEDDLE_CLAUDE_API_KEY" => "sk-ant"}

      assert %{state: :ready, binary: @bin, key?: true} = ClaudeAgent.status(env)
    end

    test "asks for a key" do
      assert %{state: :missing_key, key?: false} =
               ClaudeAgent.status(%{"HEDDLE_CLAUDE_BIN" => @bin})
    end

    test "doesn't accept a path that doesn't exist" do
      env = %{"HEDDLE_CLAUDE_BIN" => "/no/such/claude", "HEDDLE_CLAUDE_API_KEY" => "sk-ant"}

      assert %{state: :missing_binary, binary: nil} = ClaudeAgent.status(env)
    end

    test "reuses the LLM key when the provider is anthropic" do
      env = %{
        "HEDDLE_CLAUDE_BIN" => @bin,
        "HEDDLE_LLM_PROVIDER" => "anthropic",
        "HEDDLE_LLM_MODEL" => "m",
        "HEDDLE_LLM_API_KEY" => "sk-ant"
      }

      assert %{state: :ready} = ClaudeAgent.status(env)
    end

    test "doesn't send another provider's key to Anthropic" do
      env = %{
        "HEDDLE_CLAUDE_BIN" => @bin,
        "HEDDLE_LLM_PROVIDER" => "openai",
        "HEDDLE_LLM_MODEL" => "m",
        "HEDDLE_LLM_API_KEY" => "sk-openai"
      }

      assert %{state: :missing_key} = ClaudeAgent.status(env)
    end
  end

  describe "version/1" do
    @describetag :tmp_dir

    defp binary(dir, output) do
      path = Path.join(dir, "claude")
      File.write!(path, "#!/bin/sh\necho '#{output}'\n")
      File.chmod!(path, 0o755)
      path
    end

    test "reads the version", %{tmp_dir: dir} do
      assert ClaudeAgent.version(binary(dir, "2.1.318 (Claude Code)")) == "2.1.318"
    end

    test "ignores anything else the binary prints", %{tmp_dir: dir} do
      assert ClaudeAgent.version(binary(dir, ~s({"type":"noise"}))) == nil
    end

    test "survives a binary that fails", %{tmp_dir: dir} do
      path = Path.join(dir, "claude")
      File.write!(path, "#!/bin/sh\nexit 1\n")
      File.chmod!(path, 0o755)

      assert ClaudeAgent.version(path) == nil
    end
  end

  describe "args/3" do
    @opts [
      mcp_url: "http://127.0.0.1:4000/mcp",
      token: "heddle-token",
      session_id: "11111111-1111-1111-1111-111111111111",
      system: "be brief"
    ]

    defp after_flag(args, flag) do
      args |> Enum.drop_while(&(&1 != flag)) |> Enum.at(1)
    end

    test "turns every built-in tool off" do
      args = ClaudeAgent.args("hi", @opts, %{})

      assert after_flag(args, "--tools") == ""
      assert "--strict-mcp-config" in args
      assert after_flag(args, "--allowedTools") == "mcp__heddle"
      assert after_flag(args, "--permission-mode") == "dontAsk"
    end

    test "can't be steered by a message that looks like a flag" do
      prompt = "--dangerously-skip-permissions"

      assert Enum.take(ClaudeAgent.args(prompt, @opts, %{}), -2) == ["--", prompt]
    end

    test "keeps the token out of the arguments" do
      args = ClaudeAgent.args("hi", @opts, %{})

      refute Enum.any?(args, &(&1 =~ "heddle-token"))
      assert after_flag(args, "--mcp-config") =~ "${HEDDLE_MCP_TOKEN}"
    end

    test "starts or resumes the session" do
      id = @opts[:session_id]

      assert after_flag(ClaudeAgent.args("hi", @opts, %{}), "--session-id") == id

      resumed = ClaudeAgent.args("hi", Keyword.put(@opts, :resume?, true), %{})
      assert after_flag(resumed, "--resume") == id
      refute "--session-id" in resumed
    end

    test "limits spending, with a default" do
      assert after_flag(ClaudeAgent.args("hi", @opts, %{}), "--max-budget-usd") == "1"

      env = %{"HEDDLE_CLAUDE_MAX_BUDGET_USD" => "0.25"}
      assert after_flag(ClaudeAgent.args("hi", @opts, env), "--max-budget-usd") == "0.25"
    end
  end

  describe "port_env/2" do
    @env %{
      "PATH" => "/usr/bin",
      "HOME" => "/app",
      "DATABASE_URL" => "ecto://secret",
      "SECRET_KEY_BASE" => "secret",
      "HEDDLE_LLM_API_KEY" => "llm-secret",
      "HEDDLE_CLAUDE_API_KEY" => "sk-ant"
    }

    test "removes everything the binary doesn't need" do
      env = Map.new(ClaudeAgent.port_env(@env, token: "heddle-token"))

      assert env["DATABASE_URL"] == false
      assert env["SECRET_KEY_BASE"] == false
      assert env["HEDDLE_LLM_API_KEY"] == false
      assert env["HEDDLE_CLAUDE_API_KEY"] == false
      refute Map.has_key?(env, "PATH")
    end

    test "passes only the agent's own credentials" do
      env = Map.new(ClaudeAgent.port_env(@env, token: "heddle-token"))

      assert env["ANTHROPIC_API_KEY"] == "sk-ant"
      assert env["HEDDLE_MCP_TOKEN"] == "heddle-token"
    end
  end
end
