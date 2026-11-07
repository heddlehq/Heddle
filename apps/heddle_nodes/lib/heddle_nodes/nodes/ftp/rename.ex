defmodule HeddleNodes.Nodes.Ftp.Rename do
  use Bobbin.Node

  alias HeddleNodes.Integration
  alias HeddleNodes.Services.Ftp

  definition do
    Ftp.definition(
      "Rename or Move",
      "Renames a file or folder, or moves it to another path.",
      [
        %{type: :text, name: :path, label: "Current path", default: ""},
        %{type: :text, name: :new_path, label: "New path", default: ""}
      ]
    )
  end

  @impl true
  def handler(context, _input) do
    Ftp.run(context, fn connection ->
      with :ok <- :ftp.rename(connection, Ftp.path(context), Ftp.path(context, "new_path")) do
        {:ok, %{"path" => Integration.field(context, "new_path")}}
      end
    end)
  end
end
