defmodule HeddleNodes.Nodes.Ftp.Upload do
  use Bobbin.Node

  alias HeddleNodes.Integration
  alias HeddleNodes.Services.Ftp

  definition do
    Ftp.definition(
      "Upload File",
      "Writes a file on the server. The content can come from a Download node.",
      [
        %{type: :text, name: :path, label: "Path", default: ""},
        %{type: :text, name: :content, label: "Content", default: "{{result}}"}
      ]
    )
  end

  @impl true
  def handler(context, _input) do
    Ftp.run(context, fn connection ->
      with :ok <-
             :ftp.send_bin(connection, Integration.content(context, "content"), Ftp.path(context)) do
        {:ok, %{"path" => Integration.field(context, "path")}}
      end
    end)
  end
end
