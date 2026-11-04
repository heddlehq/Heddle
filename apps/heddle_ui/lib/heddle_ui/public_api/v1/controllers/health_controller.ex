defmodule HeddleUI.PublicAPI.V1.HealthController do
  use HeddleUI, :controller

  def show(conn, _params) do
    json(conn, %{status: "ok"})
  end
end
