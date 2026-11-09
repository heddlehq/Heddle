defmodule HeddleNodes.Nodes.Validate do
  @moduledoc """
  Checks a value against a schema, in the spirit of Zod, and goes on through `valid`
  or `invalid`. See `Heddle.Schema` for what a schema can say.

  Through `valid`, `result` is the value as the schema leaves it: with defaults, text
  trimmed or cased, numbers read from text when asked, and keys it doesn't know left
  out. Through `invalid`, `result` has `errors`, each with its `path`, `code` and
  `message`, `message`, all of them in one line, and `data`, the value as it came.

  The schema is plain JSON, with no placeholders, so it is checked when the flow is
  published. A schema that can't be read fails the node.
  """

  use Bobbin.Node

  alias HeddleNodes.Integration

  # Short enough to fit the drawer. The docs of the node show the options.
  @default_schema """
  {
    "name": "string",
    "email": "email",
    "age": "integer?"
  }
  """

  definition do
    %{
      name: "Validate",
      title: "Validate",
      category: :data_manipulation,
      color: "bg-emerald-500/15 text-emerald-700 dark:text-emerald-300",
      description:
        "Checks Data against a schema, like Zod. Goes on through valid with the data as the schema leaves it, or invalid with the errors.",
      icon: "hero-shield-check-solid",
      inputs: [:exec],
      outputs: ["valid", "invalid"],
      show: true,
      ui_fields: [
        %{type: :textarea, name: :validation_data, label: "Data", default: "{{result}}"},
        %{type: :textarea, name: :validation_schema, label: "Schema", default: @default_schema}
      ]
    }
  end

  @impl true
  def handler(context, _input) do
    with {:ok, schema} <- schema(context),
         {:ok, data} <- data(context) do
      case Heddle.Schema.validate(schema, data) do
        {:ok, valid} ->
          {:ok, Map.put(context, "result", valid), "valid"}

        {:error, errors} ->
          result = %{"errors" => errors, "message" => summary(errors), "data" => data}
          {:ok, Map.put(context, "result", result), "invalid"}
      end
    end
  end

  defp schema(context) do
    case Heddle.Schema.parse(context["validation_schema"]) do
      {:ok, schema} -> {:ok, schema}
      {:error, message} -> {:error, "Schema: #{message}"}
    end
  end

  # Empty Data checks nothing at all, which only an optional schema takes.
  defp data(context) do
    case String.trim(context["validation_data"] || "") do
      "" -> {:ok, nil}
      _data -> Integration.json(context, "validation_data")
    end
  end

  defp summary(errors) do
    Enum.map_join(errors, "; ", fn
      %{"path" => "", "message" => message} -> message
      %{"path" => path, "message" => message} -> "#{path}: #{message}"
    end)
  end
end
