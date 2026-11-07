defmodule HeddleNodes.Nodes.GoogleSheets.AddRows do
  use Bobbin.Node

  alias HeddleNodes.Services.GoogleSheets

  definition do
    GoogleSheets.definition(
      "Add Rows",
      "Adds rows after the last row of a range.",
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
             GoogleSheets.call(:post, GoogleSheets.values_url(context) <> ":append", token,
               params: [valueInputOption: "USER_ENTERED"],
               json: %{values: rows}
             ) do
        {:ok, %{"updated_rows" => get_in(body, ["updates", "updatedRows"]) || length(rows)}}
      end
    end)
  end
end
