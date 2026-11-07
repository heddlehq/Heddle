defmodule HeddleNodes.Nodes.GoogleSheets.CreateSheet do
  use Bobbin.Node

  alias HeddleNodes.Integration
  alias HeddleNodes.Services.GoogleSheets

  definition do
    GoogleSheets.definition(
      "Create Sheet",
      "Adds a new sheet to a spreadsheet.",
      [
        %{type: :text, name: :title, label: "Sheet name", default: ""}
      ]
    )
  end

  @impl true
  def handler(context, _input) do
    GoogleSheets.run(context, fn token ->
      title = Integration.field(context, "title")
      url = GoogleSheets.spreadsheet_url(context) <> ":batchUpdate"
      request = %{requests: [%{addSheet: %{properties: %{title: title}}}]}

      with {:ok, body} <- GoogleSheets.call(:post, url, token, json: request) do
        id = get_in(body, ["replies", Access.at(0), "addSheet", "properties", "sheetId"])

        {:ok, %{"id" => id, "title" => title}}
      end
    end)
  end
end
