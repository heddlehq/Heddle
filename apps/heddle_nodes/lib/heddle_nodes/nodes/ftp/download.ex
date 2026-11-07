defmodule HeddleNodes.Nodes.Ftp.Download do
  use Bobbin.Node

  alias HeddleNodes.Integration
  alias HeddleNodes.Services.Ftp

  definition do
    Ftp.definition(
      "Download File",
      "Reads a file from the server.",
      [
        %{type: :text, name: :path, label: "Path", default: ""}
      ]
    )
  end

  @impl true
  def handler(context, _input) do
    Ftp.run(context, fn connection ->
      with {:ok, content} <- :ftp.recv_bin(connection, Ftp.path(context)) do
        {:ok, Integration.to_text(content)}
      end
    end)
  end
end
