defmodule HeddleUI.ApiNotFoundController do
  use HeddleUI, :controller

  def show(conn, _params) do
    conn
    |> put_status(:not_found)
    |> put_view(json: HeddleUI.ErrorJSON)
    |> render(:"404")
  end
end
