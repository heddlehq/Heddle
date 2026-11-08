defmodule HeddleUI.Terminal.Session do
  @moduledoc """
  Owns one program on a pty, and carries bytes between it and whoever opened it.

  The program reaches the flows through MCP with a key of its own, which goes away with
  this process. Running a flow needs no question here: Claude Code asks before it calls a
  tool, and asking again would only be in the way.
  """

  use GenServer, restart: :temporary

  require Logger

  alias HeddleCore.ApiKeys
  alias HeddleUI.AgentChat
  alias HeddleUI.Terminal

  # Kept from the host so the program can start. The rest stays out, the secrets of this
  # install above all. That includes an Anthropic key, which would win over the account
  # the person signs in with.
  @inherited_env ~w(PATH HOME LANG LC_ALL LANGUAGE TMPDIR USER SHELL)

  @stop_timeout 2_000

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  def input(terminal, data), do: GenServer.cast(terminal, {:input, data})

  def resize(terminal, cols, rows), do: GenServer.cast(terminal, {:resize, cols, rows})

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    owner = Keyword.fetch!(opts, :owner)

    {:ok, _apps} = Application.ensure_all_started(:erlexec)

    run = AgentChat.open(Keyword.fetch!(opts, :scope), Keyword.fetch!(opts, :flow).workspace_id)
    {cols, rows} = Keyword.fetch!(opts, :size)

    {:ok, pid, os_pid} =
      :exec.run(
        Terminal.command() ++ arguments(opts[:flow]),
        [
          :stdin,
          :stdout,
          :stderr,
          :monitor,
          :pty,
          {:winsz, {rows, cols}},
          {:cd, working_dir()},
          {:env, [:clear | env(run.token)]},
          {:kill_timeout, 1}
        ]
      )

    {:ok,
     %{
       owner: owner,
       owner_ref: Process.monitor(owner),
       run: run,
       pid: pid,
       os_pid: os_pid
     }}
  end

  @impl true
  def handle_cast({:input, data}, state) do
    :exec.send(state.pid, data)
    {:noreply, state}
  end

  def handle_cast({:resize, cols, rows}, state) do
    :exec.winsz(state.os_pid, rows, cols)
    {:noreply, state}
  end

  @impl true
  def handle_info({stream, os_pid, data}, %{os_pid: os_pid} = state)
      when stream in [:stdout, :stderr] do
    send(state.owner, {:terminal_output, data})
    {:noreply, state}
  end

  def handle_info({:DOWN, os_pid, :process, _pid, _reason}, %{os_pid: os_pid} = state) do
    send(state.owner, :terminal_exited)
    {:stop, :normal, state}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{owner_ref: ref} = state) do
    {:stop, :normal, state}
  end

  def handle_info({:agent_run_confirmation, question}, state) do
    send(question.reply_to, {:agent_run_decision, question.ref, true})
    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    :exec.stop_and_wait(state.pid, @stop_timeout)
    AgentChat.close(state.run)
    ApiKeys.delete_api_key(state.run.api_key)
  catch
    :exit, reason -> Logger.warning("The terminal didn't stop cleanly: #{inspect(reason)}")
  end

  defp arguments(flow) do
    if Application.get_env(:heddle_ui, :terminal_command) do
      []
    else
      [
        "--strict-mcp-config",
        "--mcp-config",
        mcp_config(),
        "--append-system-prompt",
        instructions(flow)
      ]
    end
  end

  defp instructions(flow) do
    """
    You are running inside the editor of Heddle, a visual workflow orchestrator, and the
    person has the flow "#{flow.name}" (id #{flow.id}) open next to this terminal. "The flow"
    means that one. Work on it through the tools of the heddle MCP server: read it with
    get_flow, change it with update_flow, and prove a change with test_flow. The canvas
    refreshes by itself. When something is wrong, start from its latest run, with
    list_executions and get_execution.
    """
  end

  # The token stays out of the arguments, which any process on the host can read.
  # The forwarded proto keeps ForceSSL from redirecting this loopback request.
  defp mcp_config do
    port = HeddleUI.Mode.endpoint().config(:http)[:port]

    Jason.encode!(%{
      mcpServers: %{
        heddle: %{
          type: "http",
          url: "http://127.0.0.1:#{port}/mcp",
          headers: %{
            "Authorization" => "Bearer ${HEDDLE_MCP_TOKEN}",
            "X-Forwarded-Proto" => "https"
          }
        }
      }
    })
  end

  defp env(token) do
    inherited =
      for name <- @inherited_env, value = System.get_env(name), do: {name, value}

    inherited ++
      [{"TERM", "xterm-256color"}, {"COLORTERM", "truecolor"}, {"HEDDLE_MCP_TOKEN", token}]
  end

  defp working_dir do
    path = Path.join(System.user_home!(), ".heddle/terminal")
    File.mkdir_p!(path)
    path
  end
end
