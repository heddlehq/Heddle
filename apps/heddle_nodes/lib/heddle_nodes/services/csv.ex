defmodule HeddleNodes.Services.Csv do
  @moduledoc """
  What the Read CSV and Write CSV nodes have in common.
  """

  NimbleCSV.define(__MODULE__.Comma, separator: ",", escape: "\"")
  NimbleCSV.define(__MODULE__.Semicolon, separator: ";", escape: "\"")
  NimbleCSV.define(__MODULE__.Tab, separator: "\t", escape: "\"")

  def definition(name, description, icon, source_label) do
    %{
      name: name,
      title: name,
      category: :data_manipulation,
      color: "bg-sky-500/15 text-sky-700 dark:text-sky-300",
      description: description,
      icon: icon,
      inputs: [:exec],
      outputs: HeddleNodes.Integration.outputs(),
      show: true,
      ui_fields: [
        %{type: :text, name: :source, label: source_label, default: "result"},
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

  def source_name(context), do: context["source"] || "result"

  def parse(text, separator) do
    case parser(separator).parse_string(text, skip_headers: false) do
      [] -> []
      [headers | rows] -> Enum.map(rows, &(headers |> Enum.zip(&1) |> Map.new()))
    end
  end

  def generate(rows, separator) do
    headers = rows |> Enum.flat_map(&Map.keys/1) |> Enum.uniq()
    lines = Enum.map(rows, fn row -> Enum.map(headers, &cell(row[&1])) end)

    [headers | lines] |> parser(separator).dump_to_iodata() |> IO.iodata_to_binary()
  end

  defp cell(nil), do: ""
  defp cell(value) when is_binary(value), do: value
  defp cell(value) when is_map(value) or is_list(value), do: Jason.encode!(value)
  defp cell(value), do: to_string(value)

  defp parser("semicolon"), do: __MODULE__.Semicolon
  defp parser("tab"), do: __MODULE__.Tab
  defp parser(_separator), do: __MODULE__.Comma
end
