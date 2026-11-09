defmodule HeddleUI.SchemaErrors do
  @moduledoc """
  The errors of a Validate node (see `Heddle.Schema.validate/2`), for the person who
  filled in a form: each one by the field it is about, in their language.

  An error with `params` is one the schema wrote, and is said again here from its
  `code` and `params`. The author can write their own in each language, in
  `messages`, and a language they left out gets the one said from `params`. An error
  with only a `message` carries text the author wrote for every language.
  """

  use Gettext, backend: HeddleUI.Gettext

  @doc """
  Splits `issues` by the field each is about, the first part of its path. Returns
  `{errors, others}`: a map from field key to the first message about it, and the
  messages about anything else.
  """
  def by_field(issues, fields) when is_list(issues) do
    keys = MapSet.new(fields, & &1["key"])

    Enum.reduce(issues, {%{}, []}, fn issue, {errors, others} ->
      key = field_key(issue["path"])

      cond do
        key in keys and not Map.has_key?(errors, key) ->
          {Map.put(errors, key, message(issue)), others}

        key in keys ->
          {errors, others}

        true ->
          {errors, others ++ [message(issue)]}
      end
    end)
  end

  def by_field(_issues, _fields), do: {%{}, []}

  defp field_key(path) when is_binary(path) do
    path |> String.split([".", "["], parts: 2) |> hd()
  end

  defp field_key(_path), do: ""

  @doc """
  What an error says, in the language of the request: the author's message in that
  language, or the error said again from its `params`.
  """
  def message(%{"messages" => %{} = messages} = issue) do
    in_language(messages) || message(Map.delete(issue, "messages"))
  end

  def message(%{"params" => %{} = params, "code" => code}), do: say(code, params)
  def message(%{"message" => message}) when is_binary(message), do: message
  def message(_issue), do: gettext("Check this field.")

  # pt_BR, then pt, then another pt_* the author wrote.
  defp in_language(messages) do
    locale = Gettext.get_locale(HeddleUI.Gettext)
    language = locale |> String.split("_") |> hd()

    messages[locale] || messages[language] ||
      Enum.find_value(messages, fn {key, text} ->
        String.split(key, "_") |> hd() == language && text
      end)
  end

  defp say("required", _params), do: gettext("Fill in this field.")
  defp say("invalid_type", %{"expected" => expected}), do: expected(expected)
  defp say("invalid_enum", _params), do: gettext("Pick one of the options.")
  defp say("not_unique", _params), do: gettext("Don't pick the same option twice.")

  defp say(_code, %{"format" => format} = params), do: format(format, params)
  defp say(_code, %{"bound" => _bound} = params), do: bound(params)
  defp say(_code, _params), do: gettext("Check this field.")

  defp expected(type) when type in ["email"], do: gettext("Enter a valid email address.")
  defp expected("number"), do: gettext("Enter a number.")
  defp expected("integer"), do: gettext("Enter a whole number.")
  defp expected("date"), do: gettext("Enter a valid date.")
  defp expected("boolean"), do: gettext("Answer yes or no.")
  defp expected("url"), do: gettext("Enter a valid address, like https://example.com.")
  defp expected("string"), do: gettext("Fill in this field.")
  defp expected(_type), do: gettext("Check this field.")

  defp format("email", _params), do: expected("email")
  defp format("url", _params), do: expected("url")
  defp format("date", _params), do: expected("date")

  defp format("starts_with", %{"value" => value}),
    do: gettext("Start with %{value}.", value: value)

  defp format("ends_with", %{"value" => value}), do: gettext("End with %{value}.", value: value)
  defp format("includes", %{"value" => value}), do: gettext("Include %{value}.", value: value)
  defp format(_format, _params), do: gettext("Check the format of this field.")

  defp bound(%{"unit" => "characters", "bound" => bound, "limit" => count}) do
    case bound do
      "min" -> ngettext("Use at least 1 character.", "Use at least %{count} characters.", count)
      "max" -> ngettext("Use at most 1 character.", "Use at most %{count} characters.", count)
      _length -> ngettext("Use exactly 1 character.", "Use exactly %{count} characters.", count)
    end
  end

  defp bound(%{"unit" => "items", "bound" => bound, "limit" => count}) do
    case bound do
      "min" -> ngettext("Pick at least 1 option.", "Pick at least %{count} options.", count)
      "max" -> ngettext("Pick at most 1 option.", "Pick at most %{count} options.", count)
      _length -> ngettext("Pick exactly 1 option.", "Pick exactly %{count} options.", count)
    end
  end

  defp bound(%{"unit" => "date", "bound" => "min", "limit" => date}),
    do: gettext("Pick %{date} or later.", date: date)

  defp bound(%{"unit" => "date", "limit" => date}),
    do: gettext("Pick %{date} or earlier.", date: date)

  defp bound(%{"bound" => bound, "limit" => limit}) do
    limit = number(limit)

    case bound do
      "min" -> gettext("Enter %{limit} or more.", limit: limit)
      "max" -> gettext("Enter %{limit} or less.", limit: limit)
      "gt" -> gettext("Enter more than %{limit}.", limit: limit)
      "lt" -> gettext("Enter less than %{limit}.", limit: limit)
      _multiple -> gettext("Enter a multiple of %{limit}.", limit: limit)
    end
  end

  defp number(value) when is_float(value) do
    if value == Float.round(value), do: Integer.to_string(trunc(value)), else: to_string(value)
  end

  defp number(value), do: to_string(value)
end
