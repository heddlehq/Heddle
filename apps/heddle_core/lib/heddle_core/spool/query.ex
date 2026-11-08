defmodule HeddleCore.Spool.Query do
  @moduledoc """
  Filters and orders the rows of a Spool table, without writing SQL.

  A filter is an object from column name to what it must be:

      {"status": "open"}                        # equal
      {"total": {">": 100, "<=": 500}}          # every condition holds
      {"name": {"contains": "ana"}}             # text inside, ignoring case
      {"phone": {"empty": true}}                # nothing in it
      {"id": {"in": [1, 2, 3]}}                 # one of these

  Operators are `=`, `!=`, `>`, `>=`, `<`, `<=`, `contains`, `empty` and `in`. A value
  is converted to the column's type first, and goes to the database as a parameter,
  never into the text of the query. `id`, `created_at` and `updated_at` work too.
  """

  import Ecto.Query

  alias HeddleCore.Spool.Column

  @ops ~w(= != > >= < <= contains empty in)

  @doc "Every operator a filter takes."
  def operators, do: @ops

  @doc """
  Narrows `query`, over rows of a table with `columns`, by `filter`.

  Returns `{:ok, query}` or `{:error, message}`.
  """
  def filter(query, _columns, nil), do: {:ok, query}
  def filter(query, _columns, filter) when filter == %{}, do: {:ok, query}

  def filter(query, columns, filter) when is_map(filter) do
    Enum.reduce_while(filter, {:ok, query}, fn {name, condition}, {:ok, query} ->
      with {:ok, target} <- target(columns, to_string(name)),
           {:ok, conditions} <- conditions(condition),
           {:ok, query} <- apply_all(query, target, conditions) do
        {:cont, {:ok, query}}
      else
        {:error, message} -> {:halt, {:error, message}}
      end
    end)
  end

  def filter(_query, _columns, _filter),
    do: {:error, ~s(the filter must be an object, like {"status": "open"})}

  defp target(_columns, "id"), do: {:ok, {:field, :id, :integer}}
  defp target(_columns, "created_at"), do: {:ok, {:field, :inserted_at, :datetime}}
  defp target(_columns, "updated_at"), do: {:ok, {:field, :updated_at, :datetime}}

  defp target(columns, name) do
    case Column.find(columns, name) do
      nil -> {:error, "the table has no column #{name}"}
      column -> {:ok, {:column, column["id"], column["type"], column["name"]}}
    end
  end

  # An object of operators holds several conditions. Any other value is what the
  # column must equal, an object too for a json column.
  defp conditions(condition) when is_map(condition) and map_size(condition) > 0 do
    keys = Map.keys(condition)

    if Enum.all?(keys, &(&1 in @ops)) do
      {:ok, Enum.to_list(condition)}
    else
      {:ok, [{"=", condition}]}
    end
  end

  defp conditions(value), do: {:ok, [{"=", value}]}

  defp apply_all(query, target, conditions) do
    Enum.reduce_while(conditions, {:ok, query}, fn {op, value}, {:ok, query} ->
      case condition(target, op, value) do
        {:ok, dynamic} -> {:cont, {:ok, where(query, ^dynamic)}}
        {:error, message} -> {:halt, {:error, message}}
      end
    end)
  end

  ## The row's own fields

  defp condition({:field, field, :integer} = target, "in", values) when is_list(values) do
    with {:ok, ids} <- all(values, &integer/1, target) do
      {:ok, dynamic([r], field(r, ^field) in ^ids)}
    end
  end

  defp condition({:field, _field, _type} = target, "empty", _value),
    do: {:error, "#{name(target)} is never empty"}

  defp condition({:field, _field, _type} = target, "contains", _value),
    do: {:error, "contains works on columns, not on #{name(target)}"}

  defp condition({:field, field, type} = target, op, value) do
    with {:ok, value} <- field_value(type, value, target) do
      case op do
        "=" -> {:ok, dynamic([r], field(r, ^field) == ^value)}
        "!=" -> {:ok, dynamic([r], field(r, ^field) != ^value)}
        ">" -> {:ok, dynamic([r], field(r, ^field) > ^value)}
        ">=" -> {:ok, dynamic([r], field(r, ^field) >= ^value)}
        "<" -> {:ok, dynamic([r], field(r, ^field) < ^value)}
        "<=" -> {:ok, dynamic([r], field(r, ^field) <= ^value)}
        "in" -> {:error, "in takes a list, like [1, 2]"}
      end
    end
  end

  ## Columns

  defp condition({:column, id, _type, _name}, "=", nil), do: {:ok, empty(id)}
  defp condition({:column, id, _type, _name}, "!=", nil), do: {:ok, filled(id)}

  defp condition({:column, id, type, _name} = target, "=", value) do
    with {:ok, value} <- cast(type, value, target) do
      {:ok, dynamic([r], fragment("? @> ?", r.data, type(^%{id => value}, :map)))}
    end
  end

  defp condition({:column, id, type, _name} = target, "!=", value) do
    with {:ok, value} <- cast(type, value, target) do
      {:ok, dynamic([r], not fragment("? @> ?", r.data, type(^%{id => value}, :map)))}
    end
  end

  defp condition({:column, id, _type, _name}, "contains", value)
       when is_binary(value) or is_number(value) do
    pattern = "%" <> escape_like(to_string(value)) <> "%"
    {:ok, dynamic([r], fragment("?->>? ILIKE ?", r.data, ^id, ^pattern))}
  end

  defp condition({:column, _id, _type, _name}, "contains", _value),
    do: {:error, "contains takes a text"}

  defp condition({:column, id, _type, _name}, "empty", empty?) do
    if empty? in [false, "false", 0, "0"],
      do: {:ok, filled(id)},
      else: {:ok, empty(id)}
  end

  defp condition({:column, id, "number", _name} = target, "in", values) when is_list(values) do
    with {:ok, numbers} <- all(values, &cast("number", &1, target), target) do
      decimals = Enum.map(numbers, &decimal/1)

      {:ok,
       dynamic(
         [r],
         fragment("(?->>?)::numeric = ANY(?)", r.data, ^id, type(^decimals, {:array, :decimal}))
       )}
    end
  end

  defp condition({:column, id, type, _name} = target, "in", values)
       when is_list(values) and type in ["text", "date"] do
    with {:ok, texts} <- all(values, &cast(type, &1, target), target) do
      {:ok,
       dynamic([r], fragment("?->>? = ANY(?)", r.data, ^id, type(^texts, {:array, :string})))}
    end
  end

  defp condition({:column, _id, _type, _name} = target, "in", _values),
    do: {:error, "in takes a list of values, on a text, number or date column (#{name(target)})"}

  defp condition({:column, id, "number", _name} = target, op, value) do
    with {:ok, number} <- cast("number", value, target), :ok <- present(number, target) do
      decimal = decimal(number)

      case op do
        ">" ->
          {:ok,
           dynamic([r], fragment("(?->>?)::numeric > ?", r.data, ^id, type(^decimal, :decimal)))}

        ">=" ->
          {:ok,
           dynamic([r], fragment("(?->>?)::numeric >= ?", r.data, ^id, type(^decimal, :decimal)))}

        "<" ->
          {:ok,
           dynamic([r], fragment("(?->>?)::numeric < ?", r.data, ^id, type(^decimal, :decimal)))}

        "<=" ->
          {:ok,
           dynamic([r], fragment("(?->>?)::numeric <= ?", r.data, ^id, type(^decimal, :decimal)))}
      end
    end
  end

  defp condition({:column, id, type, _name} = target, op, value) when type in ["text", "date"] do
    with {:ok, text} <- cast(type, value, target), :ok <- present(text, target) do
      case op do
        ">" -> {:ok, dynamic([r], fragment("?->>? > ?", r.data, ^id, ^text))}
        ">=" -> {:ok, dynamic([r], fragment("?->>? >= ?", r.data, ^id, ^text))}
        "<" -> {:ok, dynamic([r], fragment("?->>? < ?", r.data, ^id, ^text))}
        "<=" -> {:ok, dynamic([r], fragment("?->>? <= ?", r.data, ^id, ^text))}
      end
    end
  end

  defp condition(target, op, _value),
    do: {:error, "#{op} doesn't compare #{name(target)}, a #{type(target)} column"}

  defp empty(id) do
    dynamic([r], fragment("coalesce(?->>?, '') = ''", r.data, ^id))
  end

  defp filled(id) do
    dynamic([r], fragment("coalesce(?->>?, '') <> ''", r.data, ^id))
  end

  ## Values

  defp cast(type, value, target) do
    case Column.cast(type, value) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, "#{inspect(value)} is not a #{type}, for #{name(target)}"}
    end
  end

  defp present(nil, target), do: {:error, "compare #{name(target)} with a value"}
  defp present(_value, _target), do: :ok

  defp field_value(:integer, value, target), do: integer(value) |> or_error(value, target)

  defp field_value(:datetime, value, target) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, at, _offset} ->
        {:ok, at}

      _other ->
        case Date.from_iso8601(value) do
          {:ok, date} -> {:ok, DateTime.new!(date, ~T[00:00:00], "Etc/UTC")}
          _other -> {:error, "#{inspect(value)} is not a date, for #{name(target)}"}
        end
    end
  end

  defp field_value(:datetime, value, target),
    do: {:error, "#{inspect(value)} is not a date, for #{name(target)}"}

  defp integer(value) when is_integer(value), do: {:ok, value}

  defp integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {integer, ""} -> {:ok, integer}
      _other -> :error
    end
  end

  defp integer(_value), do: :error

  defp or_error({:ok, value}, _raw, _target), do: {:ok, value}

  defp or_error(:error, raw, target),
    do: {:error, "#{inspect(raw)} is not a number, for #{name(target)}"}

  defp all(values, fun, target) do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, acc} ->
      case fun.(value) do
        {:ok, nil} -> {:halt, {:error, "in takes values, not null, for #{name(target)}"}}
        {:ok, cast} -> {:cont, {:ok, [cast | acc]}}
        :error -> {:halt, {:error, "#{inspect(value)} is not valid for #{name(target)}"}}
        {:error, message} -> {:halt, {:error, message}}
      end
    end)
    |> case do
      {:ok, list} -> {:ok, Enum.reverse(list)}
      error -> error
    end
  end

  defp decimal(value) when is_integer(value), do: Decimal.new(value)
  defp decimal(value) when is_float(value), do: Decimal.from_float(value)

  defp escape_like(text), do: String.replace(text, ~r/([\\%_])/, "\\\\\\1")

  defp name({:field, :inserted_at, _type}), do: "created_at"
  defp name({:field, field, _type}), do: to_string(field)
  defp name({:column, _id, _type, name}), do: name

  defp type({:field, _field, :integer}), do: "number"
  defp type({:field, _field, :datetime}), do: "date"
  defp type({:column, _id, type, _name}), do: type

  @doc """
  Orders `query` by `order`: column names, each optionally followed by `asc` or `desc`,
  separated by commas, like `"total desc, name"`. Rows without a value come last, and
  rows that tie keep the order they were added in.

  Returns `{:ok, query}` or `{:error, message}`.
  """
  def order(query, columns, order) when is_binary(order) do
    order
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.reduce_while({:ok, query}, fn part, {:ok, query} ->
      case order_by_part(query, columns, part) do
        {:ok, query} -> {:cont, {:ok, query}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, query} -> {:ok, order_by(query, [r], asc: r.id)}
      error -> error
    end
  end

  def order(query, _columns, _order), do: {:ok, order_by(query, [r], asc: r.id)}

  defp order_by_part(query, columns, part) do
    {name, direction} =
      case Regex.run(~r/\A(.+?)\s+(asc|desc)\z/i, part) do
        [_all, name, direction] -> {String.trim(name), String.downcase(direction)}
        nil -> {part, "asc"}
      end

    direction = if direction == "desc", do: :desc_nulls_last, else: :asc_nulls_last

    case target(columns, name) do
      {:ok, {:field, field, _type}} ->
        {:ok, order_by(query, [r], [{^direction, field(r, ^field)}])}

      {:ok, {:column, id, "number", _name}} ->
        {:ok, order_by(query, [r], [{^direction, fragment("(?->>?)::numeric", r.data, ^id)}])}

      {:ok, {:column, id, _type, _name}} ->
        {:ok, order_by(query, [r], [{^direction, fragment("?->>?", r.data, ^id)}])}

      error ->
        error
    end
  end

  @doc "Keeps the rows where any value holds `text`, ignoring case."
  def search(query, text) when is_binary(text) do
    case String.trim(text) do
      "" ->
        query

      text ->
        pattern = "%" <> escape_like(text) <> "%"

        where(
          query,
          [r],
          fragment(
            "EXISTS (SELECT 1 FROM jsonb_each_text(?) AS e WHERE e.value ILIKE ?)",
            r.data,
            ^pattern
          )
        )
    end
  end

  def search(query, _text), do: query
end
