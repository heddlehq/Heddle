defmodule HeddleNodes.Nodes.GoogleSheets.ListSheets do
  use Bobbin.Node

  alias HeddleNodes.Services.GoogleSheets

  definition do
    GoogleSheets.definition(
      "List Sheets",
      "Returns the sheets of a spreadsheet.",
      []
    )
  end

  @impl true
  def handler(context, _input) do
    GoogleSheets.run(context, fn token ->
      url = GoogleSheets.spreadsheet_url(context)
      params = [fields: "sheets.properties(sheetId,title)"]

      with {:ok, body} <- GoogleSheets.call(:get, url, token, params: params) do
        {:ok, Enum.map(body["sheets"] || [], &sheet(&1["properties"]))}
      end
    end)
  end

  defp sheet(properties), do: %{"id" => properties["sheetId"], "title" => properties["title"]}
end
