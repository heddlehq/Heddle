defmodule HeddleNodes.Nodes.GoogleSheets.UpdateRows do
  use Bobbin.Node

  alias HeddleNodes.Services.GoogleSheets

  definition do
    GoogleSheets.definition(
      "Update Rows",
      "Writes rows over a range, replacing what's there.",
      [
        GoogleSheets.range_field(),
        GoogleSheets.rows_field()
      ]
    )
  end

  @impl true
  def handler(context, _input) do
    GoogleSheets.run(context, fn token ->
      with {:ok, rows} <- GoogleSheets.rows(context),
           {:ok, body} <-
             GoogleSheets.call(:put, GoogleSheets.values_url(context), token,
               params: [valueInputOption: "USER_ENTERED"],
               json: %{values: rows}
             ) do
        {:ok, %{"updated_rows" => body["updatedRows"] || length(rows)}}
      end
    end)
  end
end
