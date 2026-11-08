defmodule HeddleUI.ApiEndpoint do
  use Phoenix.Endpoint, otp_app: :heddle_ui

  if code_reloading? do
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :heddle_core
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug HeddleUI.Plugs.WebhookPlug
  plug HeddleUI.Plugs.ResumePlug

  plug Plug.MethodOverride
  plug Plug.Head
  plug HeddleUI.ApiRouter
end
