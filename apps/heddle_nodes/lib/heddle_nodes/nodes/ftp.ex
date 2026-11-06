defmodule HeddleNodes.Nodes.Ftp do
  use Bobbin.Node

  alias HeddleNodes.Integration

  @timeout :timer.seconds(30)

  definition do
    %{
      name: "FTP",
      title: "FTP",
      category: :integration,
      color: "bg-orange-500/15 text-orange-700 dark:text-orange-300",
      description: "Reads, writes, lists or deletes files on an FTP server.",
      icon: "hero-server-stack-solid",
      inputs: [:exec],
      outputs: Integration.outputs(),
      show: true,
      ui_fields: [
        Integration.credential_field("ftp"),
        %{
          type: :select,
          name: :operation,
          label: "Operation",
          options: [
            %{label: "Read file", value: "get"},
            %{label: "Write file", value: "put"},
            %{label: "List files", value: "list"},
            %{label: "Delete file", value: "delete"}
          ],
          default: "get"
        },
        %{type: :text, name: :path, label: "Path", default: ""},
        %{type: :text, name: :content, label: "Content to write", default: "{{result}}"}
      ]
    }
  end

  @impl true
  def handler(context, _input) do
    with {:ok, ftp} <- Integration.credential(context, "ftp"),
         {:ok, connection} <- connect(ftp) do
      result = run(context["operation"] || "get", connection, context)
      :ftp.close(connection)

      case result do
        {:ok, value} -> Integration.success(context, value)
        {:error, reason} -> Integration.failure(context, message(reason))
      end
    else
      {:error, reason} -> Integration.failure(context, message(reason))
    end
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

  defp run("get", connection, context) do
    with {:ok, content} <- :ftp.recv_bin(connection, path(context)) do
      {:ok, Integration.to_text(content)}
    end
  end

  defp run("put", connection, context) do
    with :ok <- :ftp.send_bin(connection, Integration.field(context, "content"), path(context)) do
      {:ok, %{"path" => Integration.field(context, "path")}}
    end
  end

  defp run("delete", connection, context) do
    with :ok <- :ftp.delete(connection, path(context)) do
      {:ok, %{"path" => Integration.field(context, "path")}}
    end
  end

  defp run("list", connection, context) do
    with {:ok, names} <- :ftp.nlist(connection, path(context)) do
      {:ok, %{"files" => names |> to_string() |> String.split(~r/\r?\n/, trim: true)}}
    end
  end

  defp run(operation, _connection, _context), do: {:error, "Unknown operation: #{operation}"}

  defp path(context), do: context |> Integration.field("path") |> String.to_charlist()

  defp port(ftp) do
    case Integer.parse(to_string(ftp["port"])) do
      {port, ""} -> port
      _other -> 21
    end
  end

  defp charlist(value), do: value |> to_string() |> String.to_charlist()

  defp message(reason) when is_binary(reason), do: reason

  defp message(reason) do
    "The FTP server refused it: #{:ftp.formaterror({:error, reason})}"
  end
end
