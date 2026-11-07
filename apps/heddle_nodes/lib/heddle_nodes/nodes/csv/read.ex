defmodule HeddleNodes.Nodes.Csv.Read do
  use Bobbin.Node

  alias HeddleNodes.Integration
  alias HeddleNodes.Services.Csv
  alias HeddleNodes.Template

  definition do
    Csv.definition(
      "Read CSV",
      "Turns CSV text into a list of rows.",
      "hero-table-cells-solid",
      "CSV text"
    )
  end

  @impl true
  def handler(context, _input) do
    name = Csv.source_name(context)

    case Template.fetch(context, name) do
      text when is_binary(text) ->
        Integration.success(context, Csv.parse(text, context["separator"]))

      _other ->
        Integration.failure(context, "#{name} is not text.")
    end
  rescue
    error in NimbleCSV.ParseError -> Integration.failure(context, Exception.message(error))
  end
end
