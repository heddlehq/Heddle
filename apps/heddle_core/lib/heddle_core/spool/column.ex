defmodule HeddleCore.Spool.Column do
  @moduledoc """
  The columns of a Spool table, and how a value becomes one of their types.

  A column is a map with an `id`, which rows use to hold its value, a `name`, which
  people and nodes use, and a `type`:

    * `text`, any text. Numbers and booleans become text, lists and objects JSON.
    * `number`, an integer or a decimal, also from text like `"12.5"`.
    * `boolean`, `true` or `false`, also from `"yes"`, `"on"`, `"1"` and their opposites.
    * `date`, a date (`2026-11-08`) or a moment (`2026-11-08T10:00:00Z`), kept as ISO 8601.
    * `json`, any value.

  Rows also have `id`, `created_at` and `updated_at`, which no column can be named.
  """

  @types ~w(text number boolean date json)
  @reserved ~w(id created_at updated_at)
  @max_name 63

  @doc "The types a column can have."
  def types, do: @types

  @doc "The names every row has, which no column takes."
  def reserved, do: @reserved

  @doc "A new id for a column."
  def new_id, do: "c" <> Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)

  @doc """
  Reads the columns of a table from what a person or a node sent: a list of maps with
  `name`, `type` and, for a column the table already has, its `id`.

  Returns `{:ok, columns}` or `{:error, message}`.
  """
  def normalize(columns) when is_list(columns) do
    columns =
      Enum.map(columns, fn column ->
        column = Map.new(column, fn {key, value} -> {to_string(key), value} end)

        %{
          "id" => present(column["id"]) || new_id(),
          "name" => column["name"] |> to_string() |> String.trim(),
          "type" => to_string(column["type"] || "text")
        }
      end)

    names = Enum.map(columns, &String.downcase(&1["name"]))

    cond do
      Enum.any?(columns, &(&1["name"] == "")) ->
        {:error, "a column has no name"}

      column = Enum.find(columns, &(String.length(&1["name"]) > @max_name)) ->
        {:error, "the column name #{column["name"]} is longer than #{@max_name} characters"}

      column = Enum.find(columns, &(String.downcase(&1["name"]) in @reserved)) ->
        {:error, "#{column["name"]} is a name every row already has"}

      column = Enum.find(columns, &(&1["type"] not in @types)) ->
        {:error, "#{column["type"]} is not a column type"}

      length(Enum.uniq(names)) != length(names) ->
        {:error, "two columns have the same name"}

      true ->
        {:ok, columns}
    end
  end

  def normalize(_columns), do: {:error, "the columns must be a list"}

  defp present(value) when is_binary(value) and value != "", do: value
  defp present(_value), do: nil

  @doc "The column named `name`, ignoring case, or nil."
  def find(columns, name) when is_binary(name) do
    down = String.downcase(String.trim(name))
    Enum.find(columns, &(String.downcase(&1["name"]) == down))
  end

  def find(_columns, _name), do: nil

  @doc """
  Converts `value` to `type`. Returns `{:ok, value}`, with nil for nothing, or `:error`.
  """
  def cast(_type, nil), do: {:ok, nil}

  def cast("text", value) when is_binary(value), do: {:ok, value}
  def cast("text", value) when is_number(value) or is_boolean(value), do: {:ok, to_string(value)}
  def cast("text", value) when is_map(value) or is_list(value), do: {:ok, Jason.encode!(value)}

  def cast("number", value) when is_number(value), do: {:ok, value}

  def cast("number", value) when is_binary(value) do
    case String.trim(value) do
      "" -> {:ok, nil}
      text -> parse_number(text)
    end
  end

  def cast("boolean", value) when is_boolean(value), do: {:ok, value}
  def cast("boolean", 1), do: {:ok, true}
  def cast("boolean", 0), do: {:ok, false}

  def cast("boolean", value) when is_binary(value) do
    case value |> String.trim() |> String.downcase() do
      "" -> {:ok, nil}
      yes when yes in ~w(true yes on 1 sim) -> {:ok, true}
      no when no in ~w(false no off 0 nao não) -> {:ok, false}
      _other -> :error
    end
  end

  def cast("date", value) when is_binary(value) do
    text = String.trim(value)

    cond do
      text == "" -> {:ok, nil}
      match?({:ok, _date}, Date.from_iso8601(text)) -> {:ok, text}
      match?({:ok, _at, _offset}, DateTime.from_iso8601(text)) -> datetime(text)
      match?({:ok, _at}, NaiveDateTime.from_iso8601(text)) -> naive(text)
      true -> :error
    end
  end

  def cast("json", value), do: {:ok, value}
  def cast(_type, _value), do: :error

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

  defp datetime(text) do
    {:ok, at, _offset} = DateTime.from_iso8601(text)
    {:ok, at |> DateTime.shift_zone!("Etc/UTC") |> DateTime.to_iso8601()}
  end

  defp naive(text) do
    {:ok, at} = NaiveDateTime.from_iso8601(text)
    {:ok, NaiveDateTime.to_iso8601(at)}
  end

  @doc """
  Turns values by column name into what a row holds, by column id.

  Names are matched ignoring case, and `id`, `created_at` and `updated_at` are left
  out, so a row read from the table can be written back. With `keep_nil: true` a nil
  stays, which an update reads as clearing the column.

  Returns `{:ok, data}` or `{:error, message}`.
  """
  def to_data(columns, values, opts \\ [])

  def to_data(columns, values, opts) when is_map(values) do
    keep_nil = Keyword.get(opts, :keep_nil, false)

    Enum.reduce_while(values, {:ok, %{}}, fn {name, value}, {:ok, data} ->
      name = to_string(name)

      cond do
        String.downcase(name) in @reserved ->
          {:cont, {:ok, data}}

        column = find(columns, name) ->
          case cast(column["type"], value) do
            {:ok, nil} when not keep_nil -> {:cont, {:ok, data}}
            {:ok, cast} -> {:cont, {:ok, Map.put(data, column["id"], cast)}}
            :error -> {:halt, {:error, invalid(column, value)}}
          end

        true ->
          {:halt, {:error, unknown(columns, name)}}
      end
    end)
  end

  def to_data(_columns, _values, _opts), do: {:error, "a row must be an object"}

  defp invalid(column, value) do
    "#{inspect(value)} is not a #{column["type"]}, for the column #{column["name"]}"
  end

  defp unknown(columns, name) do
    names = Enum.map_join(columns, ", ", & &1["name"])
    "the table has no column #{name}. Its columns are: #{names}"
  end

  @doc "A row as nodes and people see it: every column by name, and the row's own fields."
  def to_row(columns, %{id: id, data: data, inserted_at: inserted_at, updated_at: updated_at}) do
    columns
    |> Map.new(&{&1["name"], Map.get(data, &1["id"])})
    |> Map.merge(%{
      "id" => id,
      "created_at" => iso(inserted_at),
      "updated_at" => iso(updated_at)
    })
  end

  defp iso(nil), do: nil
  defp iso(%DateTime{} = at), do: DateTime.to_iso8601(at)
end
