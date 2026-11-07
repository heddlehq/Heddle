defmodule HeddleNodes.Nodes.Ftp.List do
  use Bobbin.Node

  alias HeddleNodes.Services.Ftp

  definition do
    Ftp.definition(
      "List Files",
      "Returns the names of the files in a folder.",
      [
        %{type: :text, name: :path, label: "Folder", default: ""}
      ]
    )
  end

  @impl true
  def handler(context, _input) do
    Ftp.run(context, fn connection ->
      with {:ok, names} <- :ftp.nlist(connection, Ftp.path(context)) do
        {:ok, %{"files" => names |> to_string() |> String.split(~r/\r?\n/, trim: true)}}
      end
    end)
  end
end
