defmodule Heddle.Form do
  @moduledoc """
  The fields of a Form Trigger, and what a person sends through them.

  A Form Trigger keeps its fields in its `fields` control, as JSON text, so a flow
  stays plain maps of text: a list of objects with `key`, `label`, `type`, `required`,
  `placeholder` and, for a `select`, `options`. The page that shows the form, the
  validation of a publish and the run all read them through here.

  A draft may hold fields that are still being written (`parse/1` is lenient); what is
  published has to pass `validate/1`, and a submission is checked by `cast/2`, which
  never trusts what the browser sends.
  """

  @types ~w(text textarea email number date select checkbox)
  @key ~r/\A[a-zA-Z_][a-zA-Z0-9_]*\z/
  @email ~r/\A[^\s@]+@[^\s@]+\.[^\s@]+\z/
  @max_length 10_000
  @max_fields 50

  @type field :: %{required(String.t()) => term()}
  @type error ::
          :required
          | :invalid_email
          | :invalid_number
          | :invalid_date
          | :invalid_option
          | :too_long

  @doc "The types a field can have."
  def types, do: @types

  @doc "The longest text a field takes."
  def max_length, do: @max_length

  @doc "The fields a new Form Trigger starts with, as its control holds them."
  def default_json do
    JSON.encode!([
      %{"key" => "name", "label" => "Name", "type" => "text", "required" => true},
      %{"key" => "email", "label" => "Email", "type" => "email", "required" => true},
      %{"key" => "message", "label" => "Message", "type" => "textarea", "required" => false}
    ])
  end

  @doc """
  Reads the fields from what the control holds: JSON text or a list.

  Returns `{:ok, fields}`, each one with every key filled in, or `{:error, message}`
  when it isn't a list of objects. It doesn't check them: see `validate/1`.
  """
  @spec parse(term()) :: {:ok, [field()]} | {:error, String.t()}
  def parse(nil), do: {:ok, []}
  def parse(""), do: {:ok, []}

  def parse(text) when is_binary(text) do
    case JSON.decode(text) do
      {:ok, value} -> parse(value)
      {:error, _reason} -> {:error, "the fields aren't valid JSON"}
    end
  end

  def parse(fields) when is_list(fields) do
    if Enum.all?(fields, &is_map/1) do
      {:ok, Enum.map(fields, &normalize/1)}
    else
      {:error, "each field must be an object"}
    end
  end

  def parse(_value), do: {:error, "the fields must be a list"}

  @doc "Like `parse/1`, with no fields for what it can't read."
  def parse!(value) do
    case parse(value) do
      {:ok, fields} -> fields
      {:error, _message} -> []
    end
  end

  defp normalize(field) do
    field = Map.new(field, fn {key, value} -> {to_string(key), value} end)

    %{
      "key" => text(field["key"]),
      "label" => text(field["label"]),
      "type" => if(field["type"] in @types, do: field["type"], else: "text"),
      "required" => field["required"] in [true, "true", "on", "1"],
      "placeholder" => text(field["placeholder"]),
      "options" => options(field["options"])
    }
  end

  defp text(nil), do: ""
  defp text(value) when is_binary(value), do: String.trim(value)
  defp text(value), do: value |> to_string() |> String.trim()

  defp options(list) when is_list(list) do
    list |> Enum.map(&text/1) |> Enum.reject(&(&1 == "")) |> Enum.uniq()
  end

  defp options(text) when is_binary(text) do
    text |> String.split(["\r\n", "\n"]) |> options()
  end

  defp options(_value), do: []

  @doc """
  Checks the fields are complete, as a publish needs them.

  Returns `:ok` or `{:error, message}` naming the first problem.
  """
  @spec validate([field()]) :: :ok | {:error, String.t()}
  def validate(fields) when is_list(fields) do
    keys = Enum.map(fields, & &1["key"])

    cond do
      fields == [] ->
        {:error, "has no fields"}

      length(fields) > @max_fields ->
        {:error, "has more than #{@max_fields} fields"}

      field = Enum.find(fields, &(not Regex.match?(@key, &1["key"]))) ->
        {:error, "has a field with an invalid key #{inspect(field["key"])}"}

      length(Enum.uniq(keys)) != length(keys) ->
        {:error, "has two fields with the same key"}

      field = Enum.find(fields, &(&1["label"] == "")) ->
        {:error, "has a field without label (#{field["key"]})"}

      field = Enum.find(fields, &(&1["type"] == "select" and &1["options"] == [])) ->
        {:error, "has a select without options (#{field["key"]})"}

      true ->
        :ok
    end
  end

  @doc """
  Checks what a person sent against the fields, and converts it.

  Takes the params of the form, by key, and reads only the keys of the fields.
  Returns `{:ok, values}`, or `{:error, errors, values}` where `errors` maps a key to
  one of `t:error/0` and `values` holds what was sent, to show the form again.

  A checkbox is `true` or `false`, a number an integer or a float, a date
  `YYYY-MM-DD`, and an empty optional field `nil`.
  """
  @spec cast([field()], map()) :: {:ok, map()} | {:error, %{String.t() => error()}, map()}
  def cast(fields, params) when is_list(fields) and is_map(params) do
    {values, errors} =
      Enum.reduce(fields, {%{}, %{}}, fn field, {values, errors} ->
        key = field["key"]
        raw = params[key]

        case cast_value(field, raw) do
          {:ok, value} -> {Map.put(values, key, value), errors}
          {:error, error} -> {Map.put(values, key, shown(raw)), Map.put(errors, key, error)}
        end
      end)

    if errors == %{}, do: {:ok, values}, else: {:error, errors, values}
  end

  defp shown(value) when is_binary(value), do: value
  defp shown(_value), do: nil

  defp cast_value(%{"type" => "checkbox"} = field, raw) do
    checked = raw in [true, "true", "on", "1"]

    if field["required"] and not checked, do: {:error, :required}, else: {:ok, checked}
  end

  defp cast_value(field, raw) do
    value = if is_binary(raw), do: String.trim(raw), else: nil

    cond do
      value in [nil, ""] and field["required"] -> {:error, :required}
      value in [nil, ""] -> {:ok, nil}
      String.length(value) > @max_length -> {:error, :too_long}
      true -> typed(field, value)
    end
  end

  defp typed(%{"type" => "email"}, value) do
    if Regex.match?(@email, value), do: {:ok, value}, else: {:error, :invalid_email}
  end

  defp typed(%{"type" => "number"}, value) do
    normalized = String.replace(value, ",", ".")

    case Integer.parse(normalized) do
      {integer, ""} ->
        {:ok, integer}

      _other ->
        case Float.parse(normalized) do
          {float, ""} -> {:ok, float}
          _other -> {:error, :invalid_number}
        end
    end
  end

  defp typed(%{"type" => "date"}, value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, Date.to_iso8601(date)}
      {:error, _reason} -> {:error, :invalid_date}
    end
  end

  defp typed(%{"type" => "select", "options" => options}, value) do
    if value in options, do: {:ok, value}, else: {:error, :invalid_option}
  end

  defp typed(_field, value), do: {:ok, value}

  @doc """
  A key for a field from its label: `"Full name"` becomes `"full_name"`.
  """
  def key_from_label(label) when is_binary(label) do
    label
    |> String.normalize(:nfd)
    |> String.replace(~r/[^\x00-\x7F]/u, "")
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "_")
    |> String.trim("_")
    |> case do
      "" -> "field"
      <<digit, _rest::binary>> = key when digit in ?0..?9 -> "field_" <> key
      key -> key
    end
  end

  @doc "Encodes fields as the control holds them."
  def encode(fields) when is_list(fields) do
    fields
    |> Enum.map(fn field ->
      field
      |> Map.take(~w(key label type required placeholder options))
      |> Map.reject(fn {key, value} -> key in ~w(placeholder options) and value in ["", []] end)
    end)
    |> JSON.encode!()
  end
end
