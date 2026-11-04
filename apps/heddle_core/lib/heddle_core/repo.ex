defmodule HeddleCore.Repo do
  use Ecto.Repo,
    otp_app: :heddle_core,
    adapter: Ecto.Adapters.Postgres
end
