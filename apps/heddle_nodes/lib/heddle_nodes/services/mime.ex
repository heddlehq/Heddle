defmodule HeddleNodes.Services.Mime do
  @moduledoc """
  Reads emails, for the Email nodes.

  gen_smtp's decoder needs the iconv NIF to keep anything but ASCII: without it,
  an email sent as 8bit loses its accents. Mail in the wild breaks the rules, so
  nothing here raises on a broken message.
  """

  @encoded_word ~r/=\?([^?]+)\?([bBqQ])\?([^?]*)\?=/
  @param ~r/;\s*([\w*.-]+)\s*=\s*(?:"((?:[^"\\]|\\.)*)"|([^;\s]*))/
  @latin ["iso-8859-1", "iso-8859-15", "windows-1252"]

  @doc """
  Returns the headers of a message, and its parts without the multipart nesting.
  """
  def parse(raw) do
    {headers, body} = split(raw)

    %{headers: headers, parts: parts(headers, body)}
  end

  @doc """
  Returns a header in UTF-8, or an empty string.
  """
  def header(%{headers: headers}, name), do: decode_words(Map.get(headers, name, ""))

  @doc """
  Returns the text of a part in UTF-8.
  """
  def text(%{body: body, charset: charset}), do: to_utf8(body, charset)

  defp split("\r\n" <> body), do: {%{}, body}
  defp split("\n" <> body), do: {%{}, body}

  defp split(raw) do
    case :binary.match(raw, ["\r\n\r\n", "\n\n"]) do
      {position, size} ->
        <<head::binary-size(position), _blank::binary-size(size), body::binary>> = raw
        {headers(head), body}

      :nomatch ->
        {headers(raw), ""}
    end
  end

  defp headers(head) do
    ~r/\r?\n[ \t]+/
    |> Regex.replace(head, " ")
    |> String.split(~r/\r?\n/)
    |> Enum.flat_map(fn line ->
      case String.split(line, ":", parts: 2) do
        [name, value] -> [{String.downcase(String.trim(name)), String.trim(value)}]
        _other -> []
      end
    end)
    |> Enum.reverse()
    |> Map.new()
  end

  defp parts(headers, body) do
    {type, params} = value_and_params(headers["content-type"] || "text/plain")

    case {type, params["boundary"]} do
      {"multipart/" <> _subtype, boundary} when is_binary(boundary) ->
        body
        |> sections(boundary)
        |> Enum.flat_map(fn section ->
          {headers, body} = split(section)
          parts(headers, body)
        end)

      _other ->
        [part(type, params, headers, body)]
    end
  end

  defp sections(body, boundary) do
    delimiter = Regex.escape("--" <> boundary)
    [content | _epilogue] = String.split(body, ~r/(?:\A|\r?\n)#{delimiter}--/, parts: 2)

    case Regex.split(~r/(?:\A|\r?\n)#{delimiter}[ \t]*\r?\n/, content) do
      [_preamble | sections] -> sections
      [] -> []
    end
  end

  defp part(type, params, headers, body) do
    {disposition, disposition_params} = value_and_params(headers["content-disposition"] || "")

    %{
      type: type,
      charset: params["charset"] || "utf-8",
      name: file_name(disposition, disposition_params, params),
      body: decode_body(body, headers["content-transfer-encoding"])
    }
  end

  defp file_name(disposition, disposition_params, params) do
    name =
      extended(disposition_params["filename*"]) || disposition_params["filename"] ||
        extended(params["name*"]) || params["name"]

    cond do
      name -> decode_words(name)
      disposition == "attachment" -> "attachment"
      true -> nil
    end
  end

  # filename*=UTF-8''a%20b.pdf
  defp extended(nil), do: nil

  defp extended(value) do
    case String.split(value, "'", parts: 3) do
      [charset, _language, text] -> text |> URI.decode() |> to_utf8(charset)
      _other -> value
    end
  rescue
    ArgumentError -> value
  end

  defp value_and_params(header) do
    value = header |> String.split(";", parts: 2) |> hd() |> String.trim() |> String.downcase()

    params =
      @param
      |> Regex.scan(header)
      |> Map.new(fn
        [_match, name, quoted] -> {String.downcase(name), unquoted(quoted)}
        [_match, name, "", plain] -> {String.downcase(name), plain}
      end)

    {value, params}
  end

  defp unquoted(value), do: String.replace(value, ~r/\\(.)/, "\\1")

  defp decode_body(body, encoding) do
    case String.downcase(String.trim(encoding || "")) do
      "base64" -> base64(body)
      "quoted-printable" -> quoted_printable(body)
      _other -> body
    end
  end

  defp base64(text) do
    case text |> String.replace(~r/[^A-Za-z0-9+\/]/, "") |> Base.decode64(padding: false) do
      {:ok, decoded} -> decoded
      :error -> text
    end
  end

  defp quoted_printable(text) do
    :mimemail.decode_quoted_printable(text)
  rescue
    _error -> text
  catch
    _kind, _reason -> text
  end

  defp decode_words(value) do
    unfolded = String.replace(value, ~r/\?=\s+=\?/, "?==?")

    Regex.replace(@encoded_word, unfolded, fn _match, charset, encoding, text ->
      case String.downcase(encoding) do
        "b" -> text |> base64() |> to_utf8(charset)
        "q" -> text |> String.replace("_", " ") |> quoted_printable() |> to_utf8(charset)
      end
    end)
  end

  defp to_utf8(text, charset) do
    if String.downcase(charset) not in @latin and String.valid?(text) do
      text
    else
      :unicode.characters_to_binary(text, :latin1)
    end
  end
end
