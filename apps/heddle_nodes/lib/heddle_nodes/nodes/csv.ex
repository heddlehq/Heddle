defmodule HeddleNodes.Nodes.Csv do
  use Bobbin.Node

  alias HeddleNodes.Integration
  alias HeddleNodes.Template

  NimbleCSV.define(HeddleNodes.Nodes.Csv.Comma, separator: ",", escape: "\"")
  NimbleCSV.define(HeddleNodes.Nodes.Csv.Semicolon, separator: ";", escape: "\"")
  NimbleCSV.define(HeddleNodes.Nodes.Csv.Tab, separator: "\t", escape: "\"")

  definition do
    %{
      name: "CSV",
      title: "CSV",
      category: :data_manipulation,
      color: "bg-sky-500/15 text-sky-700 dark:text-sky-300",
      description: "Turns CSV text into a list of rows, or a list of rows into CSV text.",
      icon: "hero-table-cells-solid",
      inputs: [:exec],
      outputs: Integration.outputs(),
      show: true,
      ui_fields: [
        %{
          type: :select,
          name: :operation,
          label: "Operation",
          options: [
            %{label: "Read CSV", value: "parse"},
            %{label: "Write CSV", value: "generate"}
          ],
          default: "parse"
        },
        %{type: :text, name: :source, label: "Data", default: "result"},
        %{
          type: :select,
          name: :separator,
          label: "Separator",
          options: [
            %{label: "Comma", value: "comma"},
            %{label: "Semicolon", value: "semicolon"},
            %{label: "Tab", value: "tab"}
          ],
          default: "comma"
        }
      ]
    }
  end

  @impl true
  def handler(context, _input) do
    source = Template.fetch(context, context["source"] || "result")
    parser = parser(context["separator"])

    case {context["operation"] || "parse", source} do
      {"parse", text} when is_binary(text) ->
        Integration.success(context, parse(text, parser))

      {"generate", [%{} | _rest] = rows} ->
        Integration.success(context, generate(rows, parser))

      {"generate", []} ->
        Integration.success(context, "")

      {"parse", _other} ->
        Integration.failure(context, "#{context["source"]} is not text.")

      {_operation, _other} ->
        Integration.failure(context, "#{context["source"]} is not a list of rows.")
    end
  rescue
    error in NimbleCSV.ParseError -> Integration.failure(context, Exception.message(error))
  end

  defp parse(text, parser) do
    case parser.parse_string(text, skip_headers: false) do
      [] -> []
      [headers | rows] -> Enum.map(rows, &(headers |> Enum.zip(&1) |> Map.new()))
    end
  end

  defp generate(rows, parser) do
    headers = rows |> Enum.flat_map(&Map.keys/1) |> Enum.uniq()
    lines = Enum.map(rows, fn row -> Enum.map(headers, &cell(row[&1])) end)

    [headers | lines] |> parser.dump_to_iodata() |> IO.iodata_to_binary()
  end

  defp cell(nil), do: ""
  defp cell(value) when is_binary(value), do: value
  defp cell(value) when is_map(value) or is_list(value), do: Jason.encode!(value)
  defp cell(value), do: to_string(value)

  defp parser("semicolon"), do: __MODULE__.Semicolon
  defp parser("tab"), do: __MODULE__.Tab
  defp parser(_separator), do: __MODULE__.Comma
end
