defmodule HeddleNodes.Integration do
  @moduledoc """
  What the nodes that reach other services have in common.

  Each action of a service is its own node, so it shows only the fields it needs.
  They all use a stored credential, and they answer through the `success` and
  `error` outputs, so a flow can handle a service being down.
  """

  alias HeddleNodes.Template

  @color "bg-orange-500/15 text-orange-700 dark:text-orange-300"
  @logo_color "bg-gray-100 dark:bg-slate-800"
  @single_placeholder ~r/\A\{\{(.*?)\}\}\z/

  def outputs, do: ["success", "error"]

  @doc """
  Builds the definition of one action of a service.
  """
  def definition(service, action, description, fields) do
    name = "#{service.title}: #{action}"

    %{
      name: name,
      title: name,
      category: service.category,
      group: service[:group],
      color: color(service.icon),
      description: description,
      icon: service.icon,
      inputs: [:exec],
      outputs: outputs(),
      show: true,
      ui_fields: [credential_field(service.credential) | fields]
    }
  end

  # A logo brings its own colors.
  defp color("logo-" <> _name), do: @logo_color
  defp color(_icon), do: @color

  def credential_field(kind) do
    %{type: :credential, name: :credential, label: "Credential", kind: kind, default: ""}
  end

  @doc """
  Returns the values of the credential the node picked.

  heddle_core is only a test dependency of this app, so the store comes from config.
  """
  def credential(context, kind) do
    Application.fetch_env!(:heddle_nodes, :credentials_client).fetch(context["credential"], kind)
  end

  @doc """
  Calls `fun` with the credential and answers through the node's outputs.

  `fun` returns `{:ok, result}` or `{:error, message}`.
  """
  def run(context, kind, fun) do
    with {:ok, values} <- credential(context, kind),
         {:ok, result} <- fun.(values) do
      success(context, result)
    else
      {:error, message} -> failure(context, message)
    end
  end

  def field(context, name), do: Template.render(context[name], context)

  @doc """
  Returns what a file field holds.

  A field that is a single placeholder can point at what a Download node returned,
  which keeps binary files intact from one service to the other.
  """
  def content(context, name) do
    template = String.trim(context[name] || "")

    with [_match, path] <- Regex.run(@single_placeholder, template),
         %{"content" => content} = file <- Template.fetch(context, path) do
      if file["encoding"] == "base64", do: Base.decode64!(content), else: content
    else
      _other -> field(context, name)
    end
  end

  @doc """
  Reads a field that holds an image or audio: what another node returned, or a URL.

  Returns `{:ok, {bytes, media_type}}` or `{:error, message}`.
  """
  def media(context, name) do
    template = String.trim(context[name] || "")

    with [_match, path] <- Regex.run(@single_placeholder, template),
         %{"content" => _content} = file <- Template.fetch(context, path) do
      data = content(context, name)

      {:ok, {data, file["type"] || media_type(data)}}
    else
      _other -> context |> field(name) |> String.trim() |> download()
    end
  end

  defp download("http" <> _rest = url) do
    case Req.get(url, req_options(decode_body: false)) do
      {:ok, %{status: 200, body: body}} -> {:ok, {body, media_type(body)}}
      {:ok, %{status: status}} -> {:error, "The file's URL answered #{status}."}
      {:error, reason} -> {:error, "Could not get the file: #{Exception.message(reason)}"}
    end
  end

  defp download(_value), do: {:error, "There is no file here. Use {{result}} or a URL."}

  defp media_type(<<0x89, "PNG", _rest::binary>>), do: "image/png"
  defp media_type(<<0xFF, 0xD8, 0xFF, _rest::binary>>), do: "image/jpeg"
  defp media_type(<<"GIF8", _rest::binary>>), do: "image/gif"
  defp media_type(<<"RIFF", _size::32, "WEBP", _rest::binary>>), do: "image/webp"
  defp media_type(<<"RIFF", _size::32, "WAVE", _rest::binary>>), do: "audio/wav"
  defp media_type(<<"ID3", _rest::binary>>), do: "audio/mpeg"
  defp media_type(<<0xFF, 0xFB, _rest::binary>>), do: "audio/mpeg"
  defp media_type(<<"OggS", _rest::binary>>), do: "audio/ogg"
  defp media_type(<<"fLaC", _rest::binary>>), do: "audio/flac"
  defp media_type(<<_size::32, "ftyp", _rest::binary>>), do: "audio/mp4"
  defp media_type(_data), do: "application/octet-stream"

  @doc """
  Reads a field that holds JSON, or a single placeholder pointing at a value.

  Returns `{:ok, value}` or `{:error, message}`. See `HeddleNodes.Template.json/3`.
  """
  def json(context, name, check \\ fn _value -> :ok end) do
    template = String.trim(context[name] || "")

    case Regex.run(@single_placeholder, template) do
      [_match, path] -> context |> Template.fetch(path) |> decoded()
      nil -> Template.json(template, context, check)
    end
    |> case do
      {:ok, value} -> {:ok, value}
      {:error, message} -> {:error, "#{field_label(name)}: #{message}"}
    end
  end

  # A previous node can hand JSON over as text, like an HTTP response or an AI reply.
  defp decoded(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _reason} -> {:ok, value}
    end
  end

  defp decoded(value), do: {:ok, value}

  defp field_label(name), do: name |> String.replace("_", " ") |> String.capitalize()

  @doc """
  Reads a field that holds a positive number, or returns `default`.
  """
  def number(context, name, default) do
    case context |> field(name) |> String.trim() |> Integer.parse() do
      {number, ""} when number > 0 -> number
      _other -> default
    end
  end

  def success(context, result), do: {:ok, Map.put(context, "result", result), "success"}

  def failure(context, message) do
    {:ok, Map.put(context, "result", %{"error" => message}), "error"}
  end

  def req_options(options) do
    Keyword.merge(
      [retry: false, plug: Application.get_env(:heddle_nodes, :req_plug)],
      options
    )
  end

  def tls_options(host) do
    [
      verify: :verify_peer,
      cacerts: Application.get_env(:heddle_nodes, :cacerts) || :public_key.cacerts_get(),
      server_name_indication: String.to_charlist(host),
      customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
    ]
  end

  @doc """
  Makes a generated file safe to keep in a run's context, in the shape file fields read.
  """
  def to_file(data, media_type) do
    %{"content" => Base.encode64(data), "encoding" => "base64", "type" => media_type}
  end

  @doc """
  Makes what a driver returned safe to keep in a run's context, which is saved as JSON.

  Decimals become strings, because a float would lose cents.
  """
  def to_value(%Decimal{} = value), do: Decimal.to_string(value, :normal)
  def to_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  def to_value(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  def to_value(%Date{} = value), do: Date.to_iso8601(value)
  def to_value(%Time{} = value), do: Time.to_iso8601(value)

  def to_value(%_{} = value) do
    if String.Chars.impl_for(value), do: to_string(value), else: inspect(value)
  end

  def to_value(%{} = value), do: Map.new(value, fn {key, item} -> {key, to_value(item)} end)
  def to_value(value) when is_list(value), do: Enum.map(value, &to_value/1)
  def to_value(value) when is_tuple(value), do: inspect(value)

  def to_value(value) when is_atom(value) and value not in [nil, true, false],
    do: to_string(value)

  def to_value(value) when is_binary(value) do
    if String.valid?(value), do: value, else: to_text(value)
  end

  def to_value(value), do: value

  @doc """
  Makes content safe to keep in a run's context, which is saved as JSON.
  """
  def to_text(content) do
    if String.valid?(content) do
      %{"content" => content}
    else
      %{"content" => Base.encode64(content), "encoding" => "base64"}
    end
  end
end
