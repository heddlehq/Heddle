defmodule HeddleNodes.Nodes.Ftp.CreateFolder do
  use Bobbin.Node

  alias HeddleNodes.Integration
  alias HeddleNodes.Services.Ftp

  definition do
    Ftp.definition(
      "Create Folder",
      "Creates a folder on the server.",
      [
        %{type: :text, name: :path, label: "Path", default: ""}
      ]
    )
  end

  @impl true
  def handler(context, _input) do
    Ftp.run(context, fn connection ->
      with :ok <- :ftp.mkdir(connection, Ftp.path(context)) do
        {:ok, %{"path" => Integration.field(context, "path")}}
      end
    end)
  end
end
