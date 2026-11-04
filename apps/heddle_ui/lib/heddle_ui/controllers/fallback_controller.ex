defmodule HeddleUI.FallbackController do
  use HeddleUI, :controller

  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> put_view(json: HeddleUI.ErrorJSON)
    |> render(:"404")
  end

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: HeddleUI.ChangesetJSON)
    |> render("error.json", changeset: changeset)
  end
end
