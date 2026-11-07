defmodule HeddleNodes.Nodes.GoogleSheets.ClearRows do
  use Bobbin.Node

  alias HeddleNodes.Services.GoogleSheets

  definition do
    GoogleSheets.definition(
      "Clear Rows",
      "Empties the cells of a range, keeping the formatting.",
      [
        GoogleSheets.range_field()
      ]
    )
  end

  @impl true
  def handler(context, _input) do
    GoogleSheets.run(context, fn token ->
      url = GoogleSheets.values_url(context) <> ":clear"

      with {:ok, body} <- GoogleSheets.call(:post, url, token, json: %{}) do
        {:ok, %{"cleared_range" => body["clearedRange"]}}
      end
    end)
  end
end
