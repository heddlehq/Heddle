defmodule HeddleUI.LogoController do
  @moduledoc """
  The logos of the integrations written as manifests, as CSS: a `logo-<id>` class for
  each one, like the `logo-*` classes of `app.css`, so a node or a card shows it by its
  icon. They come from the manifests the instance runs and from the catalog, so an
  integration shows its logo before it is installed too.

  A logo is an SVG shown as a background image, where it runs no script.
  """

  use HeddleUI, :controller

  alias HeddleUI.Integrations.Catalog

  @id ~r/\A[a-z][a-z0-9_]*\z/

  def show(conn, _params) do
    conn
    |> put_resp_content_type("text/css")
    |> put_resp_header("cache-control", "public, max-age=300")
    |> send_resp(200, css(logos()))
  end

  defp logos do
    catalog = for {id, %{"logo" => logo}} <- Catalog.all(), do: {id, logo}

    installed =
      for %{id: id, logo: logo} when is_binary(logo) <- HeddleNodes.Manifests.all(),
          do: {id, logo}

    # What runs here wins over the catalog, whose version may be newer than the one installed.
    Map.new(catalog ++ installed)
  end

  defp css(logos) do
    for {id, logo} <- Enum.sort(logos),
        is_binary(id) and Regex.match?(@id, id),
        is_binary(logo) and String.starts_with?(String.trim(logo), "<svg"),
        into: "" do
      data = Base.encode64(String.trim(logo))
      ".logo-#{id}{background-image:url(\"data:image/svg+xml;base64,#{data}\")}\n"
    end
  end
end
