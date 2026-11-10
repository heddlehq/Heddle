defmodule HeddleNodes.Nodes.Email.Send do
  use Bobbin.Node

  alias HeddleNodes.Integration
  alias HeddleNodes.Services.Email

  definition do
    Email.definition(
      "Send Email",
      "Sends an email through SMTP. Separate several addresses with commas.",
      [
        %{type: :text, name: :to, label: "To", default: ""},
        %{type: :text, name: :cc, label: "Cc", default: ""},
        %{type: :text, name: :bcc, label: "Bcc", default: ""},
        %{type: :text, name: :subject, label: "Subject", default: ""},
        %{type: :text, name: :message, label: "Message", default: ""},
        %{
          type: :select,
          name: :format,
          label: "Format",
          options: [%{label: "Text", value: "plain"}, %{label: "HTML", value: "html"}],
          default: "plain"
        },
        %{type: :text, name: :attachment_name, label: "Attachment name", default: ""},
        %{type: :text, name: :attachment, label: "Attachment content", default: ""}
      ],
      "smtp"
    )
  end

  @impl true
  def handler(context, _input) do
    Integration.run(context, "smtp", fn smtp ->
      with {:ok, to} <- addresses(context, "to"),
           {:ok, cc} <- addresses(context, "cc"),
           {:ok, bcc} <- addresses(context, "bcc"),
           :ok <- anyone?(to ++ cc ++ bcc),
           :ok <- deliver(smtp, to, cc, bcc, context) do
        {:ok, %{"sent_to" => Enum.uniq(to ++ cc ++ bcc)}}
      end
    end)
  end

  defp addresses(context, name) do
    addresses =
      context
      |> Integration.field(name)
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)

    if Enum.all?(addresses, &address?/1) do
      {:ok, addresses}
    else
      {:error, "The #{String.capitalize(name)} field has an invalid address."}
    end
  end

  defp anyone?([]), do: {:error, "There is nobody to send it to."}
  defp anyone?(_recipients), do: :ok

  defp address?(address), do: address =~ ~r/\A[^\s@<>,]+@[^\s@<>,]+\z/

  defp deliver(smtp, to, cc, bcc, context) do
    body = message(smtp["from"], to, cc, context)
    envelope = {smtp["from"], Enum.uniq(to ++ cc ++ bcc), body}

    case :gen_smtp_client.send_blocking(envelope, options(smtp)) do
      receipt when is_binary(receipt) -> :ok
      {:error, type, details} -> {:error, "The email failed: #{inspect({type, details})}"}
      {:error, reason} -> {:error, "The email failed: #{inspect(reason)}"}
    end
  end

  # The Bcc addresses stay out of the headers, so nobody else sees them.
  defp message(from, to, cc, context) do
    headers =
      [
        {"From", from},
        {"To", Enum.join(to, ", ")},
        {"Cc", Enum.join(cc, ", ")},
        {"Subject", header(Integration.field(context, "subject"))}
      ]
      |> Enum.reject(fn {_name, value} -> value == "" end)

    :mimemail.encode(mime(headers, context))
  end

  defp mime(headers, context) do
    text = text(context)

    case Integration.field(context, "attachment_name") do
      "" ->
        put_elem(text, 2, headers)

      name ->
        {"multipart", "mixed", headers, %{}, [text, attachment(name, context)]}
    end
  end

  defp text(context) do
    subtype = if context["format"] == "html", do: "html", else: "plain"

    {"text", subtype, [], %{content_type_params: [{"charset", "utf-8"}]},
     Integration.field(context, "message")}
  end

  defp attachment(name, context) do
    params = %{
      disposition: "attachment",
      disposition_params: [{"filename", header(name)}],
      transfer_encoding: "base64"
    }

    {"application", "octet-stream", [], params, Integration.content(context, "attachment")}
  end

  # A line break here would let a value from a webhook add its own headers.
  defp header(value), do: String.replace(value, ~r/[\r\n]+/, " ")

  @doc false
  # The options of :gen_smtp_client. On 465 TLS starts with the connection and reads
  # `sockopts`, so they get the same checks as `tls_options`, which STARTTLS reads.
  def options(smtp) do
    host = smtp["host"]
    port = String.to_integer(smtp["port"] || "587")
    tls = Integration.tls_options(host)

    [
      relay: host,
      port: port,
      ssl: port == 465,
      tls: :if_available,
      auth: if(present?(smtp["username"]), do: :always, else: :never),
      username: smtp["username"],
      password: smtp["password"],
      retries: 0,
      tls_options: tls
    ] ++ if(port == 465, do: [sockopts: tls], else: [])
  end

  defp present?(value), do: is_binary(value) and value != ""
end
