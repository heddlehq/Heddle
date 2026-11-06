defmodule HeddleNodes.Nodes.GoogleSheets do
  use Bobbin.Node

  alias HeddleNodes.Integration
  alias HeddleNodes.Template

  @api "https://sheets.googleapis.com/v4/spreadsheets"
  @scope "https://www.googleapis.com/auth/spreadsheets"
  @token_lifetime 3600

  definition do
    %{
      name: "Google Sheets",
      title: "Google Sheets",
      category: :integration,
      color: "bg-orange-500/15 text-orange-700 dark:text-orange-300",
      description:
        "Reads rows from a sheet or adds rows to it, using a service account. Share the sheet with its email first.",
      icon: "hero-table-cells-solid",
      inputs: [:exec],
      outputs: Integration.outputs(),
      show: true,
      ui_fields: [
        Integration.credential_field("google"),
        %{
          type: :select,
          name: :operation,
          label: "Operation",
          options: [
            %{label: "Read rows", value: "read"},
            %{label: "Add rows", value: "append"}
          ],
          default: "read"
        },
        %{type: :text, name: :spreadsheet_id, label: "Spreadsheet ID", default: ""},
        %{type: :text, name: :range, label: "Range", default: "Sheet1!A:Z"},
        %{type: :text, name: :rows, label: "Rows to add", default: "result"}
      ]
    }
  end

  @impl true
  def handler(context, _input) do
    with {:ok, %{"json" => json}} <- Integration.credential(context, "google"),
         {:ok, account} <- decode_account(json),
         {:ok, token} <- access_token(account),
         {:ok, result} <- run(context["operation"] || "read", token, context) do
      Integration.success(context, result)
    else
      {:error, message} -> Integration.failure(context, message)
    end
  end

  defp run("read", token, context) do
    with {:ok, body} <- call(:get, url(context), token, []) do
      {:ok, Map.get(body, "values", [])}
    end
  end

  defp run("append", token, context) do
    with {:ok, rows} <- rows(context),
         {:ok, body} <-
           call(:post, url(context) <> ":append", token,
             params: [valueInputOption: "USER_ENTERED"],
             json: %{values: rows}
           ) do
      {:ok, %{"updated_rows" => get_in(body, ["updates", "updatedRows"]) || length(rows)}}
    end
  end

  defp run(operation, _token, _context), do: {:error, "Unknown operation: #{operation}"}

  defp url(context) do
    id = encode(Integration.field(context, "spreadsheet_id"))

    "#{@api}/#{id}/values/#{encode(Integration.field(context, "range"))}"
  end

  defp encode(value), do: URI.encode(value, &URI.char_unreserved?/1)

  defp call(method, url, token, options) do
    request =
      options
      |> Keyword.merge(method: method, url: url, auth: {:bearer, token})
      |> Integration.req_options()

    case Req.request(request) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{body: %{"error" => %{"message" => message}}}} -> {:error, "Google: #{message}"}
      {:ok, %{status: status}} -> {:error, "Google answered #{status}"}
      {:error, reason} -> {:error, "Could not reach Google: #{Exception.message(reason)}"}
    end
  end

  # Accepts a list of rows, one row, or a list of maps like the CSV node gives.
  defp rows(context) do
    case Template.fetch(context, context["rows"] || "result") do
      [%{} = first | _rest] = maps ->
        headers = Map.keys(first)
        {:ok, Enum.map(maps, fn row -> Enum.map(headers, &row[&1]) end)}

      [row | _rest] = rows when is_list(row) ->
        {:ok, rows}

      [_cell | _rest] = row ->
        {:ok, [row]}

      %{} = map ->
        {:ok, [Map.values(map)]}

      _other ->
        {:error, "#{context["rows"]} has no rows to add."}
    end
  end

  defp decode_account(json) do
    case Jason.decode(json) do
      {:ok, %{"client_email" => _email, "private_key" => _key} = account} -> {:ok, account}
      _other -> {:error, "The credential isn't a service account JSON."}
    end
  end

  defp access_token(account) do
    url = account["token_uri"] || "https://oauth2.googleapis.com/token"

    form = [
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: assertion(account, url)
    ]

    case Req.post(url, Integration.req_options(form: form)) do
      {:ok, %{status: 200, body: %{"access_token" => token}}} -> {:ok, token}
      {:ok, %{body: %{"error_description" => message}}} -> {:error, "Google: #{message}"}
      {:ok, %{status: status}} -> {:error, "Google refused the credential: #{status}"}
      {:error, reason} -> {:error, "Could not reach Google: #{Exception.message(reason)}"}
    end
  rescue
    _error in [MatchError, ArgumentError] -> {:error, "The service account key can't be read."}
  end

  defp assertion(account, audience) do
    now = System.system_time(:second)

    claims = %{
      iss: account["client_email"],
      scope: @scope,
      aud: audience,
      iat: now,
      exp: now + @token_lifetime
    }

    message = encode_part(%{alg: "RS256", typ: "JWT"}) <> "." <> encode_part(claims)

    [entry | _rest] = :public_key.pem_decode(account["private_key"])
    key = :public_key.pem_entry_decode(entry)

    message <> "." <> Base.url_encode64(:public_key.sign(message, :sha256, key), padding: false)
  end

  defp encode_part(map), do: map |> Jason.encode!() |> Base.url_encode64(padding: false)
end
