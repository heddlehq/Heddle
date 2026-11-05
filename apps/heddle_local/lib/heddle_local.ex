defmodule HeddleLocal do
  @moduledoc """
  Runs Heddle on one machine with nothing else installed.

  The `heddle` release ships its own Postgres. `config/runtime.exs` calls `boot/0`
  before any application starts, and the environment it returns stands in for
  what Docker or an operator would otherwise provide.
  """

  alias HeddleLocal.Postgres

  @first_port 4000
  @port_attempts 20

  @doc """
  Prepares the database and returns the environment the release runs with.

  Halts with a readable message when the database can't start, because at this
  point in the boot an exception would only print an Erlang crash report.
  """
  def boot do
    home = home()
    data = Path.join(home, "data")
    File.mkdir_p!(data)

    password = read_or_create(Path.join(data, "postgres_password"), &random_secret/0)
    secret_key_base = read_or_create(Path.join(data, "secret_key_base"), &random_secret/0)

    case Postgres.ensure_running(postgres_root(), data, password) do
      {:ok, database_url} ->
        Map.merge(python_env(home), %{
          "DATABASE_URL" => database_url,
          "SECRET_KEY_BASE" => secret_key_base,
          "PORT" => Integer.to_string(free_port(first_port())),
          "PHX_SERVER" => "true"
        })

      {:error, message} ->
        IO.puts(:stderr, "\nHeddle could not start its database.\n\n#{message}\n")
        System.halt(1)
    end
  end

  @doc """
  Keeps Python inside `home`, so removing that folder removes everything.

  Python also fails to load from a path with an accent on Windows, which the
  default cache under the user's folder may have.
  """
  def python_env(home) do
    %{
      "PYTHONX_CACHE_DIR" => Path.join([home, "cache", "pythonx"]),
      "UV_CACHE_DIR" => Path.join([home, "cache", "uv"])
    }
  end

  @doc "Where the installer puts Heddle. Everything a person creates lives under it."
  def home do
    System.get_env("HEDDLE_HOME") || default_home(:os.type(), System.get_env("LOCALAPPDATA"))
  end

  @doc false
  def default_home({:win32, _}, local_app_data) when is_binary(local_app_data) do
    Path.join(local_app_data, "Heddle")
  end

  def default_home(_os, _local_app_data), do: Path.join(System.user_home!(), ".heddle")

  @doc "Reads a generated value, creating it the first time so it survives restarts."
  def read_or_create(path, generate) do
    case File.read(path) do
      {:ok, value} when value != "" ->
        String.trim(value)

      _ ->
        value = generate.()
        File.write!(path, value)
        File.chmod!(path, 0o600)
        value
    end
  end

  @doc "Returns the first port from `port` on that this machine can listen on."
  def free_port(port, attempts \\ @port_attempts)

  def free_port(port, 0), do: port

  def free_port(port, attempts) do
    case :gen_tcp.listen(port, ip: {127, 0, 0, 1}, reuseaddr: true) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        port

      {:error, _reason} ->
        free_port(port + 1, attempts - 1)
    end
  end

  defp first_port do
    case Integer.parse(System.get_env("PORT", "")) do
      {port, ""} -> port
      _ -> @first_port
    end
  end

  defp postgres_root, do: Path.join(System.fetch_env!("RELEASE_ROOT"), "pgsql")

  defp random_secret, do: Base.url_encode64(:crypto.strong_rand_bytes(48), padding: false)
end
