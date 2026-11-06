defmodule HeddleNodes.Nodes.Email do
  use Bobbin.Node

  alias HeddleNodes.Integration

  definition do
    %{
      name: "Send Email",
      title: "Send Email",
      category: :integration,
      color: "bg-orange-500/15 text-orange-700 dark:text-orange-300",
      description: "Sends an email through SMTP. Separate several addresses with commas.",
      icon: "hero-envelope-solid",
      inputs: [:exec],
      outputs: Integration.outputs(),
      show: true,
      ui_fields: [
        Integration.credential_field("smtp"),
        %{type: :text, name: :to, label: "To", default: ""},
        %{type: :text, name: :subject, label: "Subject", default: ""},
        %{type: :text, name: :message, label: "Message", default: ""}
      ]
    }
  end

  @impl true
  def handler(context, _input) do
    with {:ok, smtp} <- Integration.credential(context, "smtp"),
         {:ok, recipients} <- recipients(context),
         :ok <- deliver(smtp, recipients, context) do
      Integration.success(context, %{"sent_to" => recipients})
    else
      {:error, message} -> Integration.failure(context, message)
    end
  end

  defp recipients(context) do
    addresses =
      context
      |> Integration.field("to")
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)

    cond do
      addresses == [] -> {:error, "There is nobody to send it to."}
      Enum.all?(addresses, &address?/1) -> {:ok, addresses}
      true -> {:error, "The To field has an invalid address."}
    end
  end

  defp address?(address), do: address =~ ~r/\A[^\s@<>,]+@[^\s@<>,]+\z/

  defp deliver(smtp, recipients, context) do
    body = message(smtp["from"], recipients, context)

    case :gen_smtp_client.send_blocking({smtp["from"], recipients, body}, options(smtp)) do
      receipt when is_binary(receipt) -> :ok
      {:error, type, details} -> {:error, "The email failed: #{inspect({type, details})}"}
      {:error, reason} -> {:error, "The email failed: #{inspect(reason)}"}
    end
  end

  defp message(from, recipients, context) do
    headers = [
      {"From", from},
      {"To", Enum.join(recipients, ", ")},
      {"Subject", header(Integration.field(context, "subject"))}
    ]

    :mimemail.encode(
      {"text", "plain", headers, %{content_type_params: [{"charset", "utf-8"}]},
       Integration.field(context, "message")}
    )
  end

  # A line break here would let a value from a webhook add its own headers.
  defp header(value), do: String.replace(value, ~r/[\r\n]+/, " ")

  defp options(smtp) do
    host = smtp["host"]
    port = String.to_integer(smtp["port"] || "587")

    [
      relay: host,
      port: port,
      ssl: port == 465,
      tls: :if_available,
      auth: if(present?(smtp["username"]), do: :always, else: :never),
      username: smtp["username"],
      password: smtp["password"],
      retries: 0,
      tls_options: tls_options(host)
    ]
  end

  defp tls_options(host) do
    [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      server_name_indication: String.to_charlist(host),
      customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
    ]
  end

  defp present?(value), do: is_binary(value) and value != ""
end
