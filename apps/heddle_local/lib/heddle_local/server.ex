defmodule HeddleLocal.Server do
  @moduledoc """
  Stops the bundled Postgres when Heddle shuts down, and opens the browser once
  the editor answers.

  The release lists `:heddle_local` first, so this outlives everything that uses
  the database.
  """

  use GenServer

  alias HeddleLocal.Postgres

  @ready_attempts 600
  @ready_interval 500

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(nil) do
    Process.flag(:trap_exit, true)
    port = System.fetch_env!("PORT") |> String.to_integer()
    Task.start(fn -> announce(port, @ready_attempts) end)
    {:ok, nil}
  end

  @impl true
  def terminate(_reason, _state) do
    root = Path.join(System.fetch_env!("RELEASE_ROOT"), "pgsql")
    Postgres.stop(root, Path.join(HeddleLocal.home(), "data"))
  end

  defp announce(_port, 0), do: :ok

  defp announce(port, attempts) do
    case :gen_tcp.connect(~c"127.0.0.1", port, [], @ready_interval) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        url = "http://localhost:#{port}"
        IO.puts("\nHeddle is running at #{url}\nPress Ctrl+C to stop it.\n")
        open_browser(url)

      {:error, _reason} ->
        Process.sleep(@ready_interval)
        announce(port, attempts - 1)
    end
  end

  defp open_browser(url) do
    unless System.get_env("HEDDLE_NO_BROWSER") do
      case browser_command(:os.type(), url) do
        {command, args} -> System.cmd(command, args, stderr_to_stdout: true)
        nil -> :ok
      end
    end
  rescue
    # No browser to open, like on a server. The address is already on screen.
    ErlangError -> :ok
  end

  @doc false
  def browser_command({:win32, _}, url), do: {"cmd", ["/c", "start", "", url]}
  def browser_command({:unix, :darwin}, url), do: {"open", [url]}

  def browser_command({:unix, _}, url) do
    if System.find_executable("xdg-open"), do: {"xdg-open", [url]}
  end
end
