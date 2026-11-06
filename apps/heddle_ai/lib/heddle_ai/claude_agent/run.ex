defmodule HeddleAI.ClaudeAgent.Run do
  @moduledoc """
  Owns one `claude -p` process and forwards its output to the caller.

  A port doesn't kill the program it started, only closes its pipes, so this process
  watches the owner and kills the program itself when the owner goes away.
  """

  use GenServer, restart: :temporary

  alias HeddleAI.ClaudeAgent.Events

  @max_line_bytes 1_048_576
  @idle_timeout to_timeout(minute: 10)

  # `claude -p` waits for piped stdin, and a port can't close it. `exec` keeps the
  # pid of the shell, which is the one this process kills.
  @launcher ~s(exec "$0" "$@" </dev/null)

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @doc """
  Lazily reads the events of a run. Must be consumed by the owner.
  """
  def stream(pid) do
    ref = Process.monitor(pid)

    Stream.resource(
      fn -> ref end,
      fn ref ->
        receive do
          {:claude_agent_event, ^pid, event} ->
            {[event], ref}

          {:claude_agent_done, ^pid} ->
            {:halt, ref}

          {:DOWN, ^ref, :process, ^pid, :normal} ->
            {:halt, ref}

          {:DOWN, ^ref, :process, ^pid, reason} ->
            {[{:error, "The agent crashed: #{inspect(reason)}"}], ref}
        after
          @idle_timeout -> {[{:error, "The agent stopped responding."}], ref}
        end
      end,
      fn ref -> Process.demonitor(ref, [:flush]) end
    )
    |> Stream.transform(false, fn
      _event, true -> {:halt, true}
      {:error, _message} = event, false -> {[event], true}
      event, false -> {[event], false}
    end)
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    owner = Keyword.fetch!(opts, :owner)

    port =
      Port.open({:spawn_executable, "/bin/sh"}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        {:line, @max_line_bytes},
        {:args, ["-c", @launcher, opts[:binary] | opts[:args]]},
        {:cd, opts[:cwd]},
        {:env, to_port_env(opts[:env])}
      ])

    {:ok,
     %{
       owner: owner,
       owner_ref: Process.monitor(owner),
       port: port,
       os_pid: os_pid(port),
       buffer: "",
       on_finish: opts[:on_finish]
     }}
  end

  @impl true
  def handle_info({port, {:data, {:noeol, chunk}}}, %{port: port} = state) do
    {:noreply, %{state | buffer: state.buffer <> chunk}}
  end

  def handle_info({port, {:data, {:eol, chunk}}}, %{port: port} = state) do
    (state.buffer <> chunk)
    |> Events.parse()
    |> Enum.each(&send(state.owner, {:claude_agent_event, self(), &1}))

    {:noreply, %{state | buffer: ""}}
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    if status != 0 do
      message = "The agent exited with status #{status}."
      send(state.owner, {:claude_agent_event, self(), {:error, message}})
    end

    send(state.owner, {:claude_agent_done, self()})
    {:stop, :normal, %{state | os_pid: nil}}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{owner_ref: ref} = state) do
    {:stop, :normal, state}
  end

  def handle_info({:EXIT, _from, _reason}, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    if state.os_pid, do: System.cmd("kill", ["-TERM", to_string(state.os_pid)])
    state.on_finish.()
  end

  # The port is already gone if the program exited right away.
  defp os_pid(port) do
    case Port.info(port, :os_pid) do
      {:os_pid, os_pid} -> os_pid
      nil -> nil
    end
  end

  defp to_port_env(env) do
    Enum.map(env, fn
      {name, false} -> {String.to_charlist(name), false}
      {name, value} -> {String.to_charlist(name), String.to_charlist(value)}
    end)
  end
end
