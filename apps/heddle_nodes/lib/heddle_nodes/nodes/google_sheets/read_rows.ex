defmodule HeddleNodes.Nodes.GoogleSheets.ReadRows do
  use Bobbin.Node

  alias HeddleNodes.Services.GoogleSheets

  definition do
    GoogleSheets.definition(
      "Read Rows",
      "Reads rows from a sheet, using a service account. Share the sheet with its email first.",
      [
        GoogleSheets.range_field()
      ]
    )
  end

  @impl true
  def handler(context, _input) do
    GoogleSheets.run(context, fn token ->
      with {:ok, body} <- GoogleSheets.call(:get, GoogleSheets.values_url(context), token) do
        {:ok, Map.get(body, "values", [])}
      end
    end)
  end
end
