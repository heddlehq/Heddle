defmodule HeddleUI.FallbackController do
  use HeddleUI, :controller

  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> put_view(json: HeddleUI.ErrorJSON)
    |> render(:"404")
  end

  # The key's owner can see this, but their role in its workspace doesn't let them do it.
  def call(conn, {:error, :forbidden}) do
    conn
    |> put_status(:forbidden)
    |> json(
      HeddleUI.ApiError.format(:forbidden, "Your role in this workspace doesn't allow this.")
    )
  end

  # Production runs what a flow publishes, and this one publishes nothing yet.
  def call(conn, {:error, :not_published}) do
    conn
    |> put_status(:conflict)
    |> json(
      HeddleUI.ApiError.format(
        :not_published,
        "This workflow has no published version. Publish it, or run its draft with version=draft."
      )
    )
  end

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: HeddleUI.ChangesetJSON)
    |> render("error.json", changeset: changeset)
  end
end
