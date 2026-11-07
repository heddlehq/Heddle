defmodule HeddleNodes.Services.Sql.Statement do
  @moduledoc """
  Turns what a person wrote in a query field into a statement and its parameters.

  A `{{placeholder}}` never becomes part of the text of the query. It goes to the
  database as a bound parameter, so a value that came from a webhook can't change what
  the query does. A string that holds a placeholder, like `'%{{name}}%'`, becomes one
  parameter with the placeholder filled in.

  A wrong guess here can only end in an error from the database, because no value is
  ever written into the text. That's why this doesn't need to know every dialect.
  """

  alias HeddleNodes.Template

  @doc """
  Returns `{:ok, statement, params}` or `{:error, message}`.

  `placeholder` gets the position of a parameter, starting after `offset`, and returns
  how the dialect writes it. `strings` lists the quotes that open a string, because
  double quotes hold a name in some dialects and a string in others.
  """
  def bind(template, context, placeholder, offset \\ 0, strings \\ [?']) do
    state = %{
      context: context,
      placeholder: placeholder,
      strings: strings,
      next: offset + 1,
      params: [],
      text: []
    }

    with {:ok, state} <- scan(template, state) do
      {:ok, state.text |> Enum.reverse() |> IO.iodata_to_binary(), Enum.reverse(state.params)}
    end
  end

  @doc """
  Splits a template into its statements, on the semicolons outside strings and comments.
  """
  def split(template, strings \\ [?']) do
    template
    |> cut(strings, [], [])
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp scan(<<>>, state), do: {:ok, state}

  defp scan("--" <> _rest = text, state) do
    {comment, rest} = line(text)

    scan(rest, write(state, comment))
  end

  defp scan("/*" <> _rest = text, state) do
    {comment, rest} = block(text)

    scan(rest, write(state, comment))
  end

  defp scan("{{" <> rest, state) do
    case String.split(rest, "}}", parts: 2) do
      [path, rest] -> scan(rest, bound(state, Template.fetch(state.context, path)))
      [_unclosed] -> {:error, "A {{ in the query is never closed."}
    end
  end

  defp scan(<<quote, rest::binary>>, state) when quote in [?', ?", ?`] do
    {body, rest} = quoted(rest, quote, <<>>)

    cond do
      not String.contains?(body, "{{") ->
        scan(rest, write(state, [quote, body, quote]))

      quote in state.strings ->
        scan(rest, bound(state, body |> unescape(quote) |> Template.render(state.context)))

      true ->
        {:error,
         "A name can't hold a {{placeholder}}: only values can. " <>
           "Use the Table field of the other nodes, which quotes it."}
    end
  end

  defp scan(<<char::utf8, rest::binary>>, state), do: scan(rest, write(state, <<char::utf8>>))
  defp scan(<<byte, rest::binary>>, state), do: scan(rest, write(state, <<byte>>))

  defp write(state, text), do: %{state | text: [text | state.text]}

  defp bound(state, value) do
    state = write(state, state.placeholder.(state.next))

    %{state | next: state.next + 1, params: [value | state.params]}
  end

  defp unescape(body, quote) do
    String.replace(body, <<quote, quote>>, <<quote>>)
  end

  # What's between two quotes, where a doubled quote is an escaped one.
  defp quoted(<<>>, _quote, body), do: {body, <<>>}

  defp quoted(<<quote, quote, rest::binary>>, quote, body) do
    quoted(rest, quote, <<body::binary, quote, quote>>)
  end

  defp quoted(<<quote, rest::binary>>, quote, body), do: {body, rest}

  defp quoted(<<char, rest::binary>>, quote, body) do
    quoted(rest, quote, <<body::binary, char>>)
  end

  defp line(text) do
    case String.split(text, "\n", parts: 2) do
      [comment, rest] -> {comment <> "\n", rest}
      [comment] -> {comment, <<>>}
    end
  end

  defp block(text) do
    case String.split(text, "*/", parts: 2) do
      [comment, rest] -> {comment <> "*/", rest}
      [comment] -> {comment, <<>>}
    end
  end

  defp cut(<<>>, _strings, current, statements) do
    Enum.reverse([current |> Enum.reverse() |> IO.iodata_to_binary() | statements])
  end

  defp cut(";" <> rest, strings, current, statements) do
    cut(rest, strings, [], [current |> Enum.reverse() |> IO.iodata_to_binary() | statements])
  end

  defp cut("--" <> _rest = text, strings, current, statements) do
    {comment, rest} = line(text)

    cut(rest, strings, [comment | current], statements)
  end

  defp cut("/*" <> _rest = text, strings, current, statements) do
    {comment, rest} = block(text)

    cut(rest, strings, [comment | current], statements)
  end

  defp cut(<<quote, rest::binary>>, strings, current, statements) when quote in [?', ?", ?`] do
    {body, rest} = quoted(rest, quote, <<>>)

    cut(rest, strings, [[quote, body, quote] | current], statements)
  end

  defp cut(<<byte, rest::binary>>, strings, current, statements) do
    cut(rest, strings, [byte | current], statements)
  end
end
