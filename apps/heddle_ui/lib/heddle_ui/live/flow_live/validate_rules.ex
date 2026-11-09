defmodule HeddleUI.FlowLive.ValidateRules do
  @moduledoc """
  The rules of a Validate node as the drawer shows them: a card per field, instead of
  the JSON of its schema (see `Heddle.Schema`), which stays the control's value.

  A rule is a map with `key`, `type`, `required`, `min`, `max`, `pattern`, `options`
  (for a choice, one per line) and `message`, from language to text. The drawer edits
  a schema this way when every field is one of these, and as JSON otherwise.

  Fields keep their order: the JSON is read with its keys in order, and written so.
  """

  @types ~w(string email url number integer date boolean enum)
  @languages ~w(en pt_BR)

  # Options a rule of the drawer writes. `trim` and `coerce` it always writes, so
  # text comes trimmed and numbers can come as text, as a form sends them.
  @known ~w(type optional min max pattern values message trim coerce)

  def types, do: @types
  def languages, do: @languages

  @doc """
  The rules of a schema, from the control's text: `{:ok, rules}`, or `:complex` when it
  holds what only JSON says, like nested objects or options the drawer doesn't show.
  """
  def from_schema(text) when is_binary(text) do
    case String.trim(text) do
      "" ->
        {:ok, []}

      text ->
        case Jason.decode(text, objects: :ordered_objects) do
          {:ok, %Jason.OrderedObject{values: fields}} -> rules(fields)
          _other -> :complex
        end
    end
  end

  def from_schema(_value), do: {:ok, []}

  defp rules(fields) do
    if Enum.any?(fields, fn {key, _value} -> key == "type" end) do
      :complex
    else
      Enum.reduce_while(fields, {:ok, []}, fn {key, value}, {:ok, rules} ->
        case rule(key, value) do
          {:ok, rule} -> {:cont, {:ok, rules ++ [rule]}}
          :complex -> {:halt, :complex}
        end
      end)
    end
  end

  defp rule(key, name) when is_binary(name) do
    {type, optional?} =
      if String.ends_with?(name, "?"),
        do: {String.trim_trailing(name, "?"), true},
        else: {name, false}

    if type in @types and type != "enum",
      do: {:ok, blank(key, type, not optional?)},
      else: :complex
  end

  defp rule(key, %Jason.OrderedObject{values: options}) do
    options = Map.new(options)

    with true <- Map.keys(options) -- @known == [],
         type when type in @types <- options["type"],
         true <- options["trim"] in [nil, true] and options["coerce"] in [nil, true],
         {:ok, message} <- message(options["message"]),
         {:ok, values} <- values(type, options["values"]) do
      {:ok,
       %{
         blank(key, type, options["optional"] != true)
         | "min" => shown(options["min"]),
           "max" => shown(options["max"]),
           "pattern" => options["pattern"] || "",
           "options" => Enum.join(values, "\n"),
           "message" => message
       }}
    else
      _other -> :complex
    end
  end

  defp rule(_key, _value), do: :complex

  defp blank(key, type, required) do
    %{
      "key" => key,
      "type" => type,
      "required" => required,
      "min" => "",
      "max" => "",
      "pattern" => "",
      "options" => "",
      "message" => Map.new(@languages, &{&1, ""})
    }
  end

  defp message(nil), do: {:ok, Map.new(@languages, &{&1, ""})}

  defp message(%Jason.OrderedObject{values: texts}) do
    texts = Map.new(texts)

    if Map.keys(texts) -- @languages == [] and Enum.all?(Map.values(texts), &is_binary/1),
      do: {:ok, Map.merge(Map.new(@languages, &{&1, ""}), texts)},
      else: :complex
  end

  defp message(_text), do: :complex

  defp values("enum", values) when is_list(values) do
    if Enum.all?(values, &is_binary/1), do: {:ok, values}, else: :complex
  end

  defp values("enum", _values), do: :complex
  defp values(_type, nil), do: {:ok, []}
  defp values(_type, _values), do: :complex

  defp shown(nil), do: ""
  defp shown(value), do: to_string(value)

  @doc "The JSON of the schema the rules describe, with the fields in order."
  def to_schema(rules) do
    # A field being named keeps its card: publishing asks for the name.
    rules
    |> Enum.map(&{String.trim(&1["key"] || ""), Jason.OrderedObject.new(options(&1))})
    |> Jason.OrderedObject.new()
    |> Jason.encode!(pretty: true)
  end

  defp options(rule) do
    type = if rule["type"] in @types, do: rule["type"], else: "string"

    [{"type", type}]
    |> add("optional", if(rule["required"] in [true, "true"], do: nil, else: true))
    |> add_bounds(type, rule)
    |> add("pattern", if(type == "string", do: present(rule["pattern"])))
    |> add("values", if(type == "enum", do: lines(rule["options"])))
    |> add("trim", if(type in ~w(string email url), do: true))
    |> add("coerce", if(type in ~w(number integer boolean), do: true))
    |> add("message", messages(rule["message"]))
  end

  defp add_bounds(options, type, rule) when type in ~w(string email url) do
    options |> add("min", count(rule["min"])) |> add("max", count(rule["max"]))
  end

  defp add_bounds(options, type, rule) when type in ~w(number integer) do
    options |> add("min", number(rule["min"])) |> add("max", number(rule["max"]))
  end

  defp add_bounds(options, "date", rule) do
    options |> add("min", date(rule["min"])) |> add("max", date(rule["max"]))
  end

  defp add_bounds(options, _type, _rule), do: options

  defp add(options, _key, nil), do: options
  defp add(options, key, value), do: options ++ [{key, value}]

  defp count(text) do
    case Integer.parse(String.trim(text || "")) do
      {count, ""} when count >= 0 -> count
      _other -> nil
    end
  end

  defp number(text) do
    text = String.trim(text || "")

    case Integer.parse(text) do
      {number, ""} ->
        number

      _other ->
        case Float.parse(text) do
          {number, ""} -> number
          _other -> nil
        end
    end
  end

  defp date(text) do
    text = String.trim(text || "")
    if match?({:ok, _date}, Date.from_iso8601(text)), do: text
  end

  defp present(text) do
    if String.trim(text || "") == "", do: nil, else: text
  end

  defp lines(text) do
    (text || "")
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp messages(%{} = texts) do
    texts =
      texts
      |> Map.take(@languages)
      |> Enum.reject(fn {_language, text} -> String.trim(text || "") == "" end)

    if texts == [], do: nil, else: Jason.OrderedObject.new(Enum.sort(texts))
  end

  defp messages(_texts), do: nil

  @doc """
  The rules a Form Trigger's fields need: each field with the type that takes its
  answer, required as it is, and a choice limited to its options.
  """
  def from_form(fields) do
    Enum.map(fields, fn field ->
      type =
        case field["type"] do
          "email" -> "email"
          "number" -> "number"
          "date" -> "date"
          "select" -> "enum"
          "checkbox" -> "boolean"
          _text -> "string"
        end

      %{
        blank(field["key"], type, field["required"] == true)
        | "options" => Enum.join(field["options"] || [], "\n")
      }
    end)
  end

  @doc "Whether the pattern of a rule is a regular expression that can be read."
  def valid_pattern?(pattern) do
    String.trim(pattern || "") == "" or match?({:ok, _regex}, Regex.compile(pattern, "u"))
  end
end
