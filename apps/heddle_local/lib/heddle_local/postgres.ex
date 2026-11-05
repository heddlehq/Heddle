defmodule HeddleLocal.Postgres do
  @moduledoc """
  Starts and stops the Postgres bundled with the `heddle` release.

  It listens on loopback only and on its own port, so it never collides with a
  Postgres already on the machine. Sockets are off because Windows has none.
  """

  @user "heddle"
  @port 54_329

  @settings """

  # Added by Heddle
  listen_addresses = '127.0.0.1'
  port = #{@port}
  unix_socket_directories = ''
  """

  @doc """
  Creates the cluster on the first run, then starts it unless it's already up.

  A cluster left running by a killed Heddle is simply reused.
  """
  def ensure_running(root, data, password) do
    cluster = cluster_path(data)

    with :ok <- init_once(root, cluster, data, password),
         :ok <- start(root, cluster, data) do
      {:ok, database_url(password)}
    end
  end

  @doc "Stops the cluster, letting open connections go."
  def stop(root, data) do
    pg_ctl(root, ["-D", cluster_path(data), "-m", "fast", "-w", "stop"])
    :ok
  end

  @doc false
  # The default `postgres` database saves a createdb step. Nothing else shares
  # this cluster, so a dedicated database would add nothing.
  def database_url(password) do
    "ecto://#{@user}:#{password}@127.0.0.1:#{@port}/postgres"
  end

  @doc false
  def cluster_path(data), do: Path.join(data, "postgres")

  defp init_once(root, cluster, data, password) do
    if File.exists?(Path.join(cluster, "PG_VERSION")) do
      :ok
    else
      init(root, cluster, data, password)
    end
  end

  defp init(root, cluster, data, password) do
    IO.puts("First run: setting up the database...")

    # initdb reads the password from a file so it never shows in a process list.
    password_file = Path.join(data, "initdb_password")
    File.write!(password_file, password)
    File.chmod!(password_file, 0o600)

    args = [
      "-D",
      cluster,
      "-U",
      @user,
      "--pwfile=#{password_file}",
      "--auth=scram-sha-256",
      "--encoding=UTF8",
      "--locale=C"
    ]

    result = run(root, "initdb", args)
    File.rm(password_file)

    with :ok <- result do
      File.write!(Path.join(cluster, "postgresql.conf"), @settings, [:append])
    end
  end

  defp start(root, cluster, data) do
    case pg_ctl(root, ["-D", cluster, "status"]) do
      {_output, 0} ->
        :ok

      _not_running ->
        log = Path.join(data, "postgres.log")

        case pg_ctl(root, ["-D", cluster, "-l", log, "-w", "-t", "60", "start"]) do
          {_output, 0} -> :ok
          {output, _status} -> {:error, output <> log_tail(log)}
        end
    end
  end

  defp run(root, name, args) do
    case System.cmd(binary(root, name), args, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, _status} -> {:error, output}
    end
  end

  defp pg_ctl(root, args) do
    System.cmd(binary(root, "pg_ctl"), args, stderr_to_stdout: true)
  end

  defp binary(root, name) do
    extension = if match?({:win32, _}, :os.type()), do: ".exe", else: ""
    Path.join([root, "bin", name <> extension])
  end

  defp log_tail(log) do
    case File.read(log) do
      {:ok, content} ->
        lines = content |> String.split("\n", trim: true) |> Enum.take(-10)
        "\n" <> Enum.join(lines, "\n")

      {:error, _reason} ->
        ""
    end
  end
end
