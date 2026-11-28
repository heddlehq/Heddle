defmodule HeddleUI.LogoControllerTest do
  # The catalog is one for the whole instance.
  use HeddleUI.ConnCase, async: false

  alias HeddleUI.Integrations.Catalog

  @svg ~s{<svg xmlns="http://www.w3.org/2000/svg"><path fill="#F00" d="M0 0h1v1z"/></svg>}

  setup do
    on_exit(&Catalog.clear/0)
  end

  test "makes a logo-<id> class of each logo in the catalog", %{conn: conn} do
    Catalog.put(%{
      "acme" => %{"id" => "acme", "manifest" => "", "logo" => @svg},
      "plain" => %{"id" => "plain", "manifest" => ""},
      ~s{bad"id} => %{"id" => ~s{bad"id}, "manifest" => "", "logo" => @svg},
      "notsvg" => %{"id" => "notsvg", "manifest" => "", "logo" => "<img src=x>"}
    })

    conn = get(conn, ~p"/integrations/logos.css")

    assert response_content_type(conn, :css) =~ "text/css"
    css = response(conn, 200)

    assert css =~
             ".logo-acme{background-image:url(\"data:image/svg+xml;base64,#{Base.encode64(@svg)}\")}"

    refute css =~ "plain"
    refute css =~ "bad"
    refute css =~ "notsvg"
  end
end
