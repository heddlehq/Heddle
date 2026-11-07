defmodule HeddleNodes.Services.Ftp do
  @moduledoc """
  An FTP connection, for the FTP nodes.
  """

  alias HeddleNodes.Integration

  @timeout :timer.seconds(30)
  @service %{title: "FTP", category: :ftp, credential: "ftp", icon: "hero-server-stack-solid"}

  def definition(action, description, fields) do
    Integration.definition(@service, action, description, fields)
  end

  @doc """
  Calls `fun` with an open connection, and closes it after.
  """
  def run(context, fun) do
    Integration.run(context, "ftp", fn ftp ->
      with {:ok, connection} <- connect(ftp) do
        result = fun.(connection)
        :ftp.close(connection)
        result
      end
      |> describe()
    end)
  end

  def path(context, name \\ "path") do
    context |> Integration.field(name) |> String.to_charlist()
  end

  defp connect(ftp) do
    options = [port: port(ftp), mode: :passive, timeout: @timeout, dtimeout: @timeout]

    with {:ok, connection} <- :ftp.open(String.to_charlist(ftp["host"]), options) do
      case :ftp.user(connection, charlist(ftp["username"]), charlist(ftp["password"])) do
        :ok ->
          {:ok, connection}

        {:error, reason} ->
          :ftp.close(connection)
          {:error, reason}
      end
    end
  end

  defp port(ftp) do
    case Integer.parse(to_string(ftp["port"])) do
      {port, ""} -> port
      _other -> 21
    end
  end

  defp charlist(value), do: value |> to_string() |> String.to_charlist()

  defp describe({:error, reason}) do
    {:error, "The FTP server refused it: #{:ftp.formaterror({:error, reason})}"}
  end

  defp describe(result), do: result
end
