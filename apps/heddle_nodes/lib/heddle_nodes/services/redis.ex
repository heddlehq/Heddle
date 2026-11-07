defmodule HeddleNodes.Services.Redis do
  @moduledoc """
  Redis and what speaks its protocol, like Valkey, KeyDB, Dragonfly and Upstash, for
  the Redis nodes.
  """

  alias HeddleNodes.Connections
  alias HeddleNodes.Integration

  @timeout :timer.seconds(30)
  @service %{
    title: "Redis",
    category: :database,
    group: "Redis",
    credential: "redis",
    icon: "logo-redis"
  }

  def definition(action, description, fields) do
    Integration.definition(@service, action, description, fields)
  end

  def key_field, do: %{type: :text, name: :key, label: "Key", default: ""}

  def value_field(label \\ "Value") do
    %{type: :textarea, name: :value, label: label, default: "{{result}}"}
  end

  @doc """
  Calls `fun` with a connection.
  """
  def run(context, fun) do
    Integration.run(context, "redis", fn values ->
      Connections.with_connection(values, fn -> connect(values) end, fun)
    end)
  end

  defp connect(%{"url" => url}) do
    options = [
      sync_connect: true,
      exit_on_disconnection: true,
      socket_opts: socket_options(url),
      timeout: @timeout
    ]

    with :ok <- Connections.check(fn -> check(url, options) end) do
      Redix.start_link(url, options)
    end
  end

  defp socket_options("rediss://" <> _rest = url) do
    Integration.tls_options(URI.parse(url).host)
  end

  defp socket_options(_url), do: []

  defp check(url, options) do
    case Redix.start_link(url, options) do
      {:ok, conn} ->
        Redix.stop(conn)
        :ok

      {:error, error} ->
        {:error, Exception.message(error)}
    end
  end

  @doc """
  Runs a command and returns what it answers, ready for a run's context.
  """
  def command(conn, command) do
    case Redix.command(conn, command, timeout: @timeout) do
      {:ok, reply} -> {:ok, Integration.to_value(reply)}
      {:error, error} -> {:error, Exception.message(error)}
    end
  end

  @doc """
  Reads a key from the node.
  """
  def key(context, name \\ "key") do
    case Integration.field(context, name) do
      "" -> {:error, "Pick a key."}
      key -> {:ok, key}
    end
  end
end
