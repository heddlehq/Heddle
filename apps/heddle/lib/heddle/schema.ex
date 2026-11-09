defmodule Heddle.Schema do
  @moduledoc """
  Schemas that describe what a value must look like, in the spirit of Zod, written as
  JSON so a person can type them in a node. See the Validate node.

  A schema is one of:

    * a type name: `"string"`, `"number"`, `"integer"`, `"boolean"`, `"date"`,
      `"email"`, `"url"`, `"uuid"`, `"array"`, `"object"` or `"any"`. A `?` at the end,
      like `"string?"`, makes it optional;
    * a list with one schema, the type of each item: `["string"]`;
    * an object with `"type"`, a type name or `enum`, `literal` or `union`, and the
      options of that type, like `{"type": "string", "min": 2}`;
    * any other object, the fields of an object: `{"name": "string", "age": "integer?"}`.
      A field called `type` needs the full form, `{"type": "object", "fields": {...}}`.

  Every type takes `optional`, `nullable`, `default` (used when the value is missing,
  and makes it optional) and `message`, which replaces the errors of that value.

    * string: `min`, `max`, `length`, `pattern`, `format` (`email`, `url`, `uuid`),
      `starts_with`, `ends_with`, `includes`, and `trim`, `lowercase`, `uppercase`,
      which change the value before it is checked. `coerce` turns numbers and booleans
      into text.
    * number and integer: `min`, `max`, `gt`, `lt`, `multiple_of`, and `coerce`, which
      reads numbers from text. An integer takes `3.0` as `3`.
    * boolean: `coerce` reads `"true"`, `"false"`, `"yes"`, `"no"`, `"on"`, `"off"`,
      `"1"`, `"0"`, `1` and `0`.
    * date: an ISO 8601 date or date and time, with `min` and `max`, also dates.
    * enum: `values`, the list of what it may be. literal: `value`, the one it must be.
    * array: `items`, `min`, `max`, `length`, `unique`.
    * object: `fields`, and `unknown`: `strip` (the default) leaves out keys it doesn't
      know, `keep` keeps them, and `error` refuses them.
    * union: `of`, a list of schemas. The first that takes the value wins.

  As in Zod, a missing value is only fine when optional, and `null` only when nullable.
  """

  @types ~w(string number integer boolean date email url uuid enum literal array object union any)
  @named ~w(string number integer boolean date email url uuid array object any)
  @formats ~w(email url uuid)

  @common ~w(type optional nullable default message)
  @options %{
    "string" =>
      ~w(min max length pattern format starts_with ends_with includes trim lowercase uppercase coerce),
    "number" => ~w(min max gt lt multiple_of coerce),
    "boolean" => ~w(coerce),
    "date" => ~w(min max),
    "enum" => ~w(values),
    "literal" => ~w(value),
    "array" => ~w(items min max length unique),
    "object" => ~w(fields unknown),
    "union" => ~w(of),
    "any" => []
  }

  @email ~r/\A[^\s@]+@[^\s@]+\.[^\s@]+\z/
  @uuid ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

  @type issue :: %{String.t() => String.t()}

  @doc """
  Reads a schema from JSON text, or from the value it decodes to.

  Returns `{:ok, schema}`, to give to `validate/2`, or `{:error, message}` saying
  what is wrong with it and where.
  """
  def parse(text) when is_binary(text) do
    case String.trim(text) do
      "" ->
        {:error, "the schema is empty"}

      text ->
        case JSON.decode(text) do
          {:ok, value} -> parse_value(value)
          # A bare type name, like email, needs no quotes.
          {:error, _reason} -> if bare?(text), do: parse_value(text), else: not_json()
        end
    end
  end

  def parse(nil), do: {:error, "the schema is empty"}
  def parse(value), do: parse_value(value)

  defp bare?(text), do: Regex.match?(~r/\A[a-z]+\??\z/, text)
  defp not_json, do: {:error, "the schema isn't valid JSON"}

  defp parse_value(value) do
    {:ok, compile(value, [])}
  catch
    {:schema, path, message} -> {:error, at(path, message)}
  end

  @doc """
  Checks `value` against a schema from `parse/1`.

  Returns `{:ok, value}`, as the schema leaves it: with defaults filled in, unknown
  keys left out and text trimmed or cased as it asks. Or `{:error, issues}`, each with
  the `path` of the value, like `items[0].email`, a `code` and a `message`.
  """
  def validate(schema, value) do
    case check(schema, {:present, value}, []) do
      {:ok, {:present, value}} -> {:ok, value}
      {:error, issues} -> {:error, issues}
    end
  end

  ## Reading a schema

  defp compile(name, path) when is_binary(name) do
    {base, optional?} =
      if String.ends_with?(name, "?"),
        do: {String.trim_trailing(name, "?"), true},
        else: {name, false}

    if base in @named do
      compile(%{"type" => base, "optional" => optional?}, path)
    else
      fail(path, "#{inspect(name)} isn't a type. Use one of: #{Enum.join(@named, ", ")}")
    end
  end

  defp compile([item], path), do: compile(%{"type" => "array", "items" => item}, path)

  defp compile(list, path) when is_list(list),
    do: fail(path, "a list in a schema holds one schema, the one of its items")

  defp compile(%{"type" => type} = written, path) when type in @types do
    {kind, schema} = kind(type, written)
    allowed = @common ++ Map.fetch!(@options, kind)

    case Map.keys(written) -- allowed do
      [] -> :ok
      [key | _] -> fail(path, "#{inspect(key)} isn't an option of #{article(type)}")
    end

    schema
    |> base(path)
    |> Map.merge(options(kind, schema, path))
    |> Map.put(:type, kind)
    |> Map.put(:name, type)
  end

  defp compile(%{} = fields, path) do
    compile(%{"type" => "object", "fields" => fields}, path)
  end

  defp compile(_value, path),
    do: fail(path, "a schema is a type name, a list with one schema, or an object")

  # email, url and uuid are strings with a format, and an integer is a whole number.
  defp kind(type, schema) when type in @formats,
    do: {"string", Map.put_new(schema, "format", type)}

  defp kind("integer", schema), do: {"number", Map.put(schema, "integer", true)}
  defp kind(type, schema), do: {type, schema}

  defp base(schema, path) do
    default =
      case Map.fetch(schema, "default") do
        {:ok, value} -> {:some, value}
        :error -> :none
      end

    %{
      optional: flag(schema, "optional", path) or default != :none,
      nullable: flag(schema, "nullable", path),
      default: default,
      message: text(schema, "message", path),
      integer: Map.get(schema, "integer", false)
    }
  end

  defp options("string", schema, path) do
    format = text(schema, "format", path)

    if format && format not in @formats do
      fail(path, "format is one of: #{Enum.join(@formats, ", ")}")
    end

    %{
      min: count(schema, "min", path),
      max: count(schema, "max", path),
      length: count(schema, "length", path),
      pattern: pattern(schema, path),
      format: format,
      starts_with: text(schema, "starts_with", path),
      ends_with: text(schema, "ends_with", path),
      includes: text(schema, "includes", path),
      trim: flag(schema, "trim", path),
      lowercase: flag(schema, "lowercase", path),
      uppercase: flag(schema, "uppercase", path),
      coerce: flag(schema, "coerce", path)
    }
  end

  defp options("number", schema, path) do
    multiple = number(schema, "multiple_of", path)

    if multiple != nil and multiple <= 0 do
      fail(path, "multiple_of must be more than 0")
    end

    %{
      min: number(schema, "min", path),
      max: number(schema, "max", path),
      gt: number(schema, "gt", path),
      lt: number(schema, "lt", path),
      multiple_of: multiple,
      coerce: flag(schema, "coerce", path)
    }
  end

  defp options("boolean", schema, path), do: %{coerce: flag(schema, "coerce", path)}

  defp options("date", schema, path) do
    %{min: date_option(schema, "min", path), max: date_option(schema, "max", path)}
  end

  defp options("enum", schema, path) do
    case schema["values"] do
      [_ | _] = values -> %{values: values}
      _other -> fail(path, "an enum needs values, a list of what it may be")
    end
  end

  defp options("literal", schema, path) do
    if Map.has_key?(schema, "value"),
      do: %{value: schema["value"]},
      else: fail(path, "a literal needs value, the one it must be")
  end

  defp options("array", schema, path) do
    %{
      items: compile(Map.get(schema, "items", "any"), path ++ [:items]),
      min: count(schema, "min", path),
      max: count(schema, "max", path),
      length: count(schema, "length", path),
      unique: flag(schema, "unique", path)
    }
  end

  defp options("object", schema, path) do
    fields =
      case Map.get(schema, "fields", %{}) do
        %{} = fields ->
          Map.new(fields, fn {key, field} -> {key, compile(field, path ++ [key])} end)

        _other ->
          fail(path, "fields is an object, from each key to its schema")
      end

    unknown = Map.get(schema, "unknown", if(schema["fields"], do: "strip", else: "keep"))

    if unknown not in ~w(strip keep error) do
      fail(path, "unknown is strip, keep or error")
    end

    %{fields: fields, unknown: unknown}
  end

  defp options("union", schema, path) do
    case schema["of"] do
      [_, _ | _] = options ->
        %{of: options |> Enum.with_index() |> Enum.map(fn {s, i} -> compile(s, path ++ [i]) end)}

      _other ->
        fail(path, "a union needs of, a list of at least two schemas")
    end
  end

  defp options("any", _schema, _path), do: %{}

  defp flag(schema, key, path) do
    case Map.get(schema, key, false) do
      value when is_boolean(value) -> value
      _other -> fail(path, "#{key} is true or false")
    end
  end

  defp text(schema, key, path) do
    case Map.get(schema, key) do
      value when is_binary(value) or is_nil(value) -> value
      _other -> fail(path, "#{key} is text")
    end
  end

  defp count(schema, key, path) do
    case Map.get(schema, key) do
      value when (is_integer(value) and value >= 0) or is_nil(value) -> value
      _other -> fail(path, "#{key} is a whole number, 0 or more")
    end
  end

  defp number(schema, key, path) do
    case Map.get(schema, key) do
      value when is_number(value) or is_nil(value) -> value
      _other -> fail(path, "#{key} is a number")
    end
  end

  defp pattern(schema, path) do
    case text(schema, "pattern", path) do
      nil ->
        nil

      source ->
        case Regex.compile(source, "u") do
          {:ok, regex} -> {source, regex}
          {:error, _reason} -> fail(path, "pattern isn't a valid regular expression")
        end
    end
  end

  defp date_option(schema, key, path) do
    case text(schema, key, path) do
      nil ->
        nil

      value ->
        case to_datetime(value) do
          {:ok, at} -> {value, at}
          :error -> fail(path, "#{key} is a date, like 2026-12-24")
        end
    end
  end

  defp fail(path, message), do: throw({:schema, path, message})

  defp at([], message), do: message
  defp at(path, message), do: "#{format_path(path)}: #{message}"

  defp article(type) when type in ~w(any array enum email integer object url union uuid),
    do: "an #{type}"

  defp article(type), do: "a #{type}"

  ## Checking a value

  # A value is `{:present, value}` or `:missing`, so a missing key and a null differ.
  defp check(%{default: {:some, default}} = schema, :missing, path),
    do: check(%{schema | default: :none}, {:present, default}, path)

  defp check(%{optional: true}, :missing, _path), do: {:ok, :missing}
  defp check(%{type: "any"}, :missing, _path), do: {:ok, :missing}
  defp check(_schema, :missing, path), do: error(path, "required", "Required")

  defp check(%{nullable: true}, {:present, nil}, _path), do: {:ok, {:present, nil}}
  defp check(%{type: "any"}, {:present, value}, _path), do: {:ok, {:present, value}}

  defp check(schema, {:present, value}, path) do
    case check_value(schema, value, path) do
      {:ok, value} -> {:ok, {:present, value}}
      {:error, issues} -> {:error, own_message(schema, path, issues)}
    end
  end

  # The message of a schema stands for the errors of its own value, not of what's in it.
  defp own_message(%{message: nil}, _path, issues), do: issues

  defp own_message(%{message: message}, path, issues) do
    here = format_path(path)

    Enum.map(issues, fn issue ->
      if issue["path"] == here,
        do: issue |> Map.put("message", message) |> Map.delete("params"),
        else: issue
    end)
  end

  defp check_value(%{type: "string"} = schema, value, path) do
    with {:ok, text} <- string(schema, value, path) do
      text = transform(schema, text)

      checks(text, path, [
        length_check(schema, String.length(text), "characters"),
        fn -> pattern_check(schema, text) end,
        fn -> format_check(schema.format, text) end,
        fn -> affix(schema.starts_with, &String.starts_with?(text, &1), "starts_with") end,
        fn -> affix(schema.ends_with, &String.ends_with?(text, &1), "ends_with") end,
        fn -> affix(schema.includes, &String.contains?(text, &1), "includes") end
      ])
    end
  end

  defp check_value(%{type: "number"} = schema, value, path) do
    with {:ok, number} <- number_value(schema, value, path) do
      checks(number, path, [
        fn -> bound("min", schema.min, number >= (schema.min || 0)) end,
        fn -> bound("max", schema.max, number <= (schema.max || 0)) end,
        fn -> bound("gt", schema.gt, number > (schema.gt || 0)) end,
        fn -> bound("lt", schema.lt, number < (schema.lt || 0)) end,
        fn -> multiple_check(schema.multiple_of, number) end
      ])
    end
  end

  defp check_value(%{type: "boolean"} = schema, value, path) do
    case boolean(schema, value) do
      {:ok, boolean} -> {:ok, boolean}
      :error -> type_issue(schema, value, path)
    end
  end

  defp check_value(%{type: "date"} = schema, value, path) do
    with true <- is_binary(value) || type_issue(schema, value, path),
         {:ok, at} <- date(String.trim(value), path) do
      checks(String.trim(value), path, [
        fn ->
          date_bound(schema.min, &(DateTime.compare(at, &1) != :lt), "too_small", "on or after")
        end,
        fn ->
          date_bound(schema.max, &(DateTime.compare(at, &1) != :gt), "too_big", "on or before")
        end
      ])
    end
  end

  defp check_value(%{type: "enum", values: values}, value, path) do
    if value in values,
      do: {:ok, value},
      else:
        error(path, "invalid_enum", "Must be one of: #{Enum.map_join(values, ", ", &show/1)}", %{
          "values" => values
        })
  end

  defp check_value(%{type: "literal", value: expected}, value, path) do
    if value == expected,
      do: {:ok, value},
      else: error(path, "invalid_literal", "Must be #{show(expected)}", %{"value" => expected})
  end

  defp check_value(%{type: "array"} = schema, value, path) when is_list(value) do
    results =
      value
      |> Enum.with_index()
      |> Enum.map(fn {item, index} -> check(schema.items, {:present, item}, path ++ [index]) end)

    case collect(results) do
      {:ok, items} ->
        items = Enum.map(items, fn {:present, item} -> item end)

        checks(items, path, [
          length_check(schema, length(items), "items"),
          fn ->
            if schema.unique and length(Enum.uniq(items)) != length(items),
              do: {"not_unique", "Must not repeat items", %{}}
          end
        ])

      {:error, issues} ->
        {:error, issues}
    end
  end

  defp check_value(%{type: "object"} = schema, value, path) when is_map(value) do
    fields =
      Enum.map(schema.fields, fn {key, field} ->
        present = if Map.has_key?(value, key), do: {:present, value[key]}, else: :missing
        {key, check(field, present, path ++ [key])}
      end)

    unknown = Map.keys(value) -- Map.keys(schema.fields)

    unknown_issues =
      if schema.unknown == "error",
        do: Enum.map(unknown, &issue_map(path ++ [&1], "unknown_key", "Isn't allowed here", %{})),
        else: []

    case {collect(Enum.map(fields, &elem(&1, 1))), unknown_issues} do
      {{:ok, _values}, []} ->
        kept = if schema.unknown == "keep", do: Map.take(value, unknown), else: %{}

        {:ok,
         Enum.reduce(fields, kept, fn
           {key, {:ok, {:present, field}}}, acc -> Map.put(acc, key, field)
           {_key, {:ok, :missing}}, acc -> acc
         end)}

      {{:ok, _values}, issues} ->
        {:error, issues}

      {{:error, issues}, more} ->
        {:error, issues ++ more}
    end
  end

  defp check_value(%{type: "union", of: options}, value, path) do
    Enum.find_value(options, fn option ->
      case check(option, {:present, value}, path) do
        {:ok, {:present, value}} -> {:ok, value}
        _other -> nil
      end
    end) || error(path, "invalid_union", "Doesn't match any of the allowed shapes")
  end

  defp check_value(schema, value, path), do: type_issue(schema, value, path)

  defp string(_schema, value, _path) when is_binary(value), do: {:ok, value}

  defp string(%{coerce: true}, value, _path) when is_number(value) or is_boolean(value),
    do: {:ok, to_string(value)}

  defp string(schema, value, path), do: type_issue(schema, value, path)

  defp transform(schema, text) do
    text
    |> then(&if(schema.trim, do: String.trim(&1), else: &1))
    |> then(&if(schema.lowercase, do: String.downcase(&1), else: &1))
    |> then(&if(schema.uppercase, do: String.upcase(&1), else: &1))
  end

  defp number_value(schema, value, path) when is_binary(value) do
    with true <- schema[:coerce] == true,
         {:ok, number} <- parse_number(String.trim(value)) do
      number_value(schema, number, path)
    else
      _other -> type_issue(schema, value, path)
    end
  end

  defp number_value(%{integer: true} = schema, value, path) when is_float(value) do
    if value == Float.round(value),
      do: {:ok, trunc(value)},
      else: type_issue(schema, value, path)
  end

  defp number_value(_schema, value, _path) when is_number(value), do: {:ok, value}
  defp number_value(schema, value, path), do: type_issue(schema, value, path)

  defp parse_number(text) do
    case Integer.parse(text) do
      {integer, ""} ->
        {:ok, integer}

      _other ->
        case Float.parse(text) do
          {float, ""} -> {:ok, float}
          _other -> :error
        end
    end
  end

  defp boolean(_schema, value) when is_boolean(value), do: {:ok, value}

  defp boolean(%{coerce: true}, value) when is_binary(value) do
    case value |> String.trim() |> String.downcase() do
      truthy when truthy in ~w(true yes on 1) -> {:ok, true}
      falsy when falsy in ~w(false no off 0) -> {:ok, false}
      _other -> :error
    end
  end

  defp boolean(%{coerce: true}, 1), do: {:ok, true}
  defp boolean(%{coerce: true}, 0), do: {:ok, false}
  defp boolean(_schema, _value), do: :error

  defp date(text, path) do
    case to_datetime(text) do
      {:ok, at} ->
        {:ok, at}

      :error ->
        error(
          path,
          "invalid_format",
          "Must be a date, like 2026-12-24 or 2026-12-24T18:00:00Z",
          %{
            "format" => "date"
          }
        )
    end
  end

  defp to_datetime(text) do
    with {:error, _} <- datetime(text),
         {:error, _} <- naive(text),
         {:error, _} <- Date.from_iso8601(text) do
      :error
    else
      {:ok, %Date{} = date} -> {:ok, DateTime.new!(date, ~T[00:00:00])}
      {:ok, at} -> {:ok, at}
    end
  end

  defp datetime(text) do
    case DateTime.from_iso8601(text) do
      {:ok, at, _offset} -> {:ok, at}
      {:error, reason} -> {:error, reason}
    end
  end

  defp naive(text) do
    with {:ok, naive} <- NaiveDateTime.from_iso8601(text),
         do: {:ok, DateTime.from_naive!(naive, "Etc/UTC")}
  end

  # Runs the checks of a value in order, and stops at the first that fails, as Zod
  # reports one problem per value.
  defp checks(value, path, checks) do
    Enum.find_value(checks, fn check ->
      case check.() do
        {code, message} -> error(path, code, message)
        {code, message, params} -> error(path, code, message, params)
        nil -> nil
      end
    end) || {:ok, value}
  end

  defp length_check(schema, size, unit) do
    fn ->
      cond do
        schema.length && size != schema.length ->
          {if(size < schema.length, do: "too_small", else: "too_big"),
           "Must have exactly #{plural(schema.length, unit)}",
           %{"bound" => "length", "limit" => schema.length, "unit" => unit}}

        schema.min && size < schema.min ->
          {"too_small", "Must have at least #{plural(schema.min, unit)}",
           %{"bound" => "min", "limit" => schema.min, "unit" => unit}}

        schema.max && size > schema.max ->
          {"too_big", "Must have at most #{plural(schema.max, unit)}",
           %{"bound" => "max", "limit" => schema.max, "unit" => unit}}

        true ->
          nil
      end
    end
  end

  defp pattern_check(%{pattern: nil}, _text), do: nil

  defp pattern_check(%{pattern: {source, regex}}, text) do
    unless Regex.match?(regex, text),
      do: {"invalid_format", "Must match #{source}", %{"format" => "pattern"}}
  end

  defp format_check(nil, _text), do: nil

  defp format_check("email", text) do
    unless Regex.match?(@email, text),
      do: {"invalid_format", "Must be an email address", %{"format" => "email"}}
  end

  defp format_check("uuid", text) do
    unless Regex.match?(@uuid, text),
      do: {"invalid_format", "Must be a UUID", %{"format" => "uuid"}}
  end

  defp format_check("url", text) do
    case URI.parse(text) do
      %URI{scheme: scheme, host: host}
      when scheme in ["http", "https"] and host not in [nil, ""] ->
        nil

      _other ->
        {"invalid_format", "Must be a URL, like https://example.com", %{"format" => "url"}}
    end
  end

  @affixes %{
    "starts_with" => "Must start with",
    "ends_with" => "Must end with",
    "includes" => "Must include"
  }

  defp affix(nil, _matches?, _format), do: nil

  defp affix(part, matches?, format) do
    unless matches?.(part),
      do:
        {"invalid_format", "#{@affixes[format]} #{inspect(part)}",
         %{"format" => format, "value" => part}}
  end

  @bounds %{
    "min" => {"too_small", "Must be at least"},
    "max" => {"too_big", "Must be at most"},
    "gt" => {"too_small", "Must be more than"},
    "lt" => {"too_big", "Must be less than"}
  }

  defp bound(_key, nil, _ok?), do: nil

  defp bound(key, limit, ok?) do
    {code, message} = @bounds[key]
    unless ok?, do: {code, "#{message} #{show(limit)}", %{"bound" => key, "limit" => limit}}
  end

  defp multiple_check(nil, _number), do: nil

  defp multiple_check(step, number) do
    quotient = number / step

    unless abs(quotient - Float.round(quotient)) < 1.0e-9,
      do:
        {"not_multiple", "Must be a multiple of #{show(step)}",
         %{"bound" => "multiple_of", "limit" => step}}
  end

  defp date_bound(nil, _ok?, _code, _word), do: nil

  defp date_bound({source, at}, ok?, code, word) do
    unless ok?.(at),
      do:
        {code, "Must be #{word} #{source}",
         %{
           "bound" => if(code == "too_small", do: "min", else: "max"),
           "limit" => source,
           "unit" => "date"
         }}
  end

  defp collect(results) do
    {values, issues} =
      Enum.reduce(results, {[], []}, fn
        {:ok, value}, {values, issues} -> {[value | values], issues}
        {:error, more}, {values, issues} -> {values, issues ++ more}
      end)

    if issues == [], do: {:ok, Enum.reverse(values)}, else: {:error, issues}
  end

  defp type_issue(%{name: name}, value, path) do
    error(path, "invalid_type", "Expected #{article(name)}, got #{describe(value)}", %{
      "expected" => name
    })
  end

  # `params` holds what the message says in numbers and names, so an interface can
  # say it in another language. A message the schema gives has none.
  defp error(path, code, message, params \\ %{}),
    do: {:error, [issue_map(path, code, message, params)]}

  defp issue_map(path, code, message, params) do
    %{"path" => format_path(path), "code" => code, "message" => message, "params" => params}
  end

  defp describe(nil), do: "null"
  defp describe(value) when is_binary(value), do: "text"
  defp describe(value) when is_boolean(value), do: "a boolean"
  defp describe(value) when is_integer(value), do: "an integer"
  defp describe(value) when is_float(value), do: "a number"
  defp describe(value) when is_list(value), do: "a list"
  defp describe(value) when is_map(value), do: "an object"
  defp describe(_value), do: "something else"

  defp plural(1, unit), do: "1 #{String.trim_trailing(unit, "s")}"
  defp plural(count, unit), do: "#{count} #{unit}"

  defp show(value) when is_binary(value), do: inspect(value)

  defp show(value) when is_float(value) do
    if value == Float.round(value),
      do: value |> trunc() |> Integer.to_string(),
      else: to_string(value)
  end

  defp show(value) when is_number(value) or is_boolean(value), do: to_string(value)
  defp show(nil), do: "null"
  defp show(value), do: JSON.encode!(value)

  @doc false
  def format_path(path) do
    Enum.reduce(path, "", fn
      index, "" when is_integer(index) -> "[#{index}]"
      index, acc when is_integer(index) -> "#{acc}[#{index}]"
      :items, acc -> "#{acc}[]"
      key, "" -> key
      key, acc -> "#{acc}.#{key}"
    end)
  end
end
