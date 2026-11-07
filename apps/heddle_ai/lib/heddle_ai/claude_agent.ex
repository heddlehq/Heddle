defmodule HeddleAI.ClaudeAgent do
  @moduledoc """
  Runs the `claude` CLI as a flow copilot.

  Each message is one supervised `claude -p`, tied to the previous ones through its
  session id. The process is confined to the MCP tools of this instance: built-in
  tools are off, so it can't read files or run commands, and it starts with a clean
  environment, so the secrets of the host never reach it.

  Anthropic doesn't allow third-party products to offer claude.ai login, so this only
  takes an API key. It is shown to people as "Claude Agent", as the Agent SDK branding
  rules ask of integrations.
  """

  alias HeddleAI.ClaudeAgent.Run
  alias HeddleAI.LLM

  @default_budget_usd "1"
  @version_timeout 5_000

  # Kept from the host so the binary can start. Everything else is removed.
  @inherited_env ~w(PATH HOME LANG LC_ALL LANGUAGE TMPDIR)

  @type status :: %{
          state: :ready | :missing_binary | :missing_key,
          binary: String.t() | nil,
          key?: boolean()
        }

  @spec status(%{String.t() => String.t()}) :: status()
  def status(env \\ System.get_env()) do
    binary = binary(env)
    key? = api_key(env) != nil

    state =
      cond do
        binary == nil -> :missing_binary
        not key? -> :missing_key
        true -> :ready
      end

    %{state: state, binary: binary, key?: key?}
  end

  @spec ready?() :: boolean()
  def ready?, do: status().state == :ready

  @doc """
  Asks the binary for its version, giving up rather than holding the caller.
  """
  @spec version(String.t()) :: String.t() | nil
  def version(binary) do
    task = Task.async(fn -> System.cmd(binary, ["--version"], stderr_to_stdout: true) end)

    case Task.yield(task, @version_timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, {output, 0}} -> parse_version(output)
      _other -> nil
    end
  end

  # The binary may print warnings too, and only a version belongs on the page.
  defp parse_version(output) do
    case Regex.run(~r/\b\d+\.\d+\.\d+\S*/, output) do
      [version] -> version
      nil -> nil
    end
  end

  @doc """
  Streams a reply as `{:text_delta, text}` events, like `HeddleAI.AI.stream_text/2`.

  ## Options

    * `:mcp_url` - where this instance serves MCP
    * `:token` - API key the agent calls MCP with
    * `:session_id` - UUID of the conversation
    * `:resume?` - whether that conversation already exists
    * `:system` - appended to the system prompt
    * `:on_finish` - called once when the process is gone, however it ended

  The process dies with the caller.
  """
  def stream_text(prompt, opts) do
    env = System.get_env()
    %{state: :ready, binary: binary} = status(env)

    spec =
      {Run,
       owner: self(),
       binary: binary,
       args: args(prompt, opts, env),
       env: port_env(env, opts),
       cwd: working_dir(),
       on_finish: Keyword.get(opts, :on_finish, fn -> :ok end)}

    {:ok, pid} = DynamicSupervisor.start_child(HeddleAI.ClaudeAgent.Supervisor, spec)

    {:ok, %{stream: Run.stream(pid)}}
  end

  @doc false
  def args(prompt, opts, env) do
    session =
      if Keyword.get(opts, :resume?, false),
        do: ["--resume", opts[:session_id]],
        else: ["--session-id", opts[:session_id]]

    [
      "-p",
      "--bare",
      "--output-format",
      "stream-json",
      "--verbose",
      "--include-partial-messages",
      "--tools",
      "",
      "--strict-mcp-config",
      "--mcp-config",
      mcp_config(opts[:mcp_url]),
      "--allowedTools",
      "mcp__heddle",
      "--permission-mode",
      "dontAsk",
      "--max-budget-usd",
      budget(env),
      "--append-system-prompt",
      Keyword.get(opts, :system, "")
    ] ++ session ++ ["--", prompt]
  end

  @doc false
  def port_env(env, opts) do
    removed = for {name, _value} <- env, name not in @inherited_env, do: {name, false}

    removed ++
      [
        {"ANTHROPIC_API_KEY", api_key(env)},
        {"HEDDLE_MCP_TOKEN", opts[:token]}
      ]
  end

  # The token stays out of the arguments, which any process on the host can read.
  # The forwarded proto keeps ForceSSL from redirecting this loopback request.
  defp mcp_config(url) do
    Jason.encode!(%{
      mcpServers: %{
        heddle: %{
          type: "http",
          url: url,
          headers: %{
            "Authorization" => "Bearer ${HEDDLE_MCP_TOKEN}",
            "X-Forwarded-Proto" => "https"
          }
        }
      }
    })
  end

  # The AI page comes first, then the environment, then whatever the PATH finds.
  defp binary(env) do
    case saved_binary() || read(env, "HEDDLE_CLAUDE_BIN") do
      nil -> System.find_executable("claude")
      path -> if File.regular?(path), do: path
    end
  end

  # The AI page is in heddle_core, which isn't a dependency of this app. Tests that have
  # no database turn this off in config.
  defp saved_binary do
    case Application.get_env(:heddle_ai, :claude_binary, &HeddleNodes.Services.AI.claude_binary/0) do
      nil -> nil
      read -> read.()
    end
  end

  defp api_key(env) do
    read(env, "HEDDLE_CLAUDE_API_KEY") || anthropic_llm_key(env)
  end

  defp anthropic_llm_key(env) do
    if LLM.status(env).provider == "anthropic", do: read(env, "HEDDLE_LLM_API_KEY")
  end

  defp budget(env), do: read(env, "HEDDLE_CLAUDE_MAX_BUDGET_USD") || @default_budget_usd

  # Sessions are stored per directory, and a fixed empty one has nothing to pick up.
  defp working_dir do
    path = Path.join(System.tmp_dir!(), "heddle-claude-agent")
    File.mkdir_p!(path)
    path
  end

  defp read(env, name) do
    case Map.get(env, name) do
      value when value in [nil, ""] -> nil
      value -> value
    end
  end
end
