defmodule HeddleUI.SpoolExportController do
  @moduledoc """
  Downloads a Spool table as CSV, row by row as the database reads them.
  """

  use HeddleUI, :controller

  alias HeddleCore.Spool

  def show(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope

    case Spool.get_table(scope, id) do
      nil ->
        conn |> put_status(:not_found) |> put_view(HeddleUI.ErrorHTML) |> render(:"404")

      table ->
        conn =
          conn
          |> put_resp_content_type("text/csv")
          |> put_resp_header(
            "content-disposition",
            ~s(attachment; filename="#{filename(table.name)}.csv")
          )
          |> send_chunked(200)

        {:ok, conn} =
          Spool.export_csv(scope, table, conn, fn line, conn ->
            case chunk(conn, line) do
              {:ok, conn} -> {:cont, conn}
              {:error, _closed} -> {:halt, conn}
            end
          end)

        conn
    end
  end

  defp filename(name) do
    case name |> String.replace(~r/[^\w\-]+/u, "_") |> String.trim("_") do
      "" -> "table"
      name -> name
    end
  end
end
