defmodule HeddleNodes.Services.GoogleSheets do
  @moduledoc """
  The Google Sheets API with a service account, for the Google Sheets nodes.
  """

  alias HeddleNodes.Integration
  alias HeddleNodes.Template

  @api "https://sheets.googleapis.com/v4/spreadsheets"
  @scope "https://www.googleapis.com/auth/spreadsheets"
  @token_lifetime 3600
  @service %{
    title: "Google Sheets",
    category: :google_sheets,
    credential: "google",
    icon: "logo-google-sheets"
  }

  def definition(action, description, fields) do
    Integration.definition(@service, action, description, [spreadsheet_field() | fields])
  end

  def range_field, do: %{type: :text, name: :range, label: "Range", default: "Sheet1!A:Z"}
  def rows_field, do: %{type: :text, name: :rows, label: "Rows", default: "result"}

  defp spreadsheet_field do
    %{type: :text, name: :spreadsheet_id, label: "Spreadsheet ID", default: ""}
  end

  @doc """
  Calls `fun` with an access token.
  """
  def run(context, fun) do
    Integration.run(context, "google", fn %{"json" => json} ->
      with {:ok, account} <- decode_account(json),
           {:ok, token} <- access_token(account) do
        fun.(token)
      end
    end)
  end

  def spreadsheet_url(context) do
    "#{@api}/#{encode(Integration.field(context, "spreadsheet_id"))}"
  end

  def values_url(context) do
    "#{spreadsheet_url(context)}/values/#{encode(Integration.field(context, "range"))}"
  end

  defp encode(value), do: URI.encode(value, &URI.char_unreserved?/1)

  def call(method, url, token, options \\ []) do
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

  @doc """
  Accepts a list of rows, one row, or a list of maps like the CSV node gives.
  """
  def rows(context) do
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
        {:error, "#{context["rows"]} has no rows."}
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
