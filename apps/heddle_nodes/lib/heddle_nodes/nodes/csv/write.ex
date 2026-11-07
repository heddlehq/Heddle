defmodule HeddleNodes.Nodes.Csv.Write do
  use Bobbin.Node

  alias HeddleNodes.Integration
  alias HeddleNodes.Services.Csv
  alias HeddleNodes.Template

  definition do
    Csv.definition(
      "Write CSV",
      "Turns a list of rows into CSV text.",
      "hero-document-text-solid",
      "Rows"
    )
  end

  @impl true
  def handler(context, _input) do
    name = Csv.source_name(context)

    case Template.fetch(context, name) do
      [%{} | _rest] = rows ->
        Integration.success(context, Csv.generate(rows, context["separator"]))

      [] ->
        Integration.success(context, "")

      _other ->
        Integration.failure(context, "#{name} is not a list of rows.")
    end
  end
end
