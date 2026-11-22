defmodule HeddleCore.Credentials.OAuthApp do
  @moduledoc "The app a system admin registered with a service, see `HeddleCore.Credentials.OAuth`."

  use Ecto.Schema

  schema "oauth_apps" do
    field :kind, :string
    field :client_id, :string
    field :client_secret, :binary, redact: true

    timestamps(type: :utc_datetime)
  end
end
