defmodule HeddleUI.Plugs.SetLocaleTest do
  use HeddleUI.ConnCase, async: true

  alias HeddleUI.Plugs.SetLocale

  describe "call/2" do
    test "sets locale from params", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> Map.put(:params, %{"locale" => "pt_BR"})
        |> Plug.Conn.fetch_query_params()

      conn = SetLocale.call(conn, nil)

      assert conn.assigns.locale == "pt_BR"
    end

    test "ignores unsupported locale from params", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> Map.put(:params, %{"locale" => "invalid"})
        |> Plug.Conn.fetch_query_params()

      conn = SetLocale.call(conn, nil)

      assert conn.assigns.locale == "en"
    end

    test "sets locale from session", %{conn: conn} do
      conn = init_test_session(conn, %{locale: "pt_BR"})
      conn = Plug.Conn.fetch_query_params(conn)
      conn = SetLocale.call(conn, nil)

      assert conn.assigns.locale == "pt_BR"
    end

    test "ignores unsupported locale from session", %{conn: conn} do
      conn = init_test_session(conn, %{locale: "invalid"})
      conn = Plug.Conn.fetch_query_params(conn)
      conn = SetLocale.call(conn, nil)

      assert conn.assigns.locale == "en"
    end

    test "sets locale from accept-language header", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> Plug.Conn.fetch_query_params()

      conn = %{conn | req_headers: [{"accept-language", "pt_BR,en;q=0.9"}]}
      conn = SetLocale.call(conn, nil)

      assert conn.assigns.locale == "pt_BR"
    end

    test "reads the tags browsers send, like pt-BR, and a language alone", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> Plug.Conn.fetch_query_params()

      for {header, locale} <- [
            {"pt-BR,pt;q=0.9,en;q=0.8", "pt_BR"},
            {"pt-br", "pt_BR"},
            {"pt", "pt_BR"},
            {"de-DE,en-US;q=0.8", "en"}
          ] do
        assert SetLocale.call(%{conn | req_headers: [{"accept-language", header}]}, nil).assigns.locale ==
                 locale
      end
    end

    test "defaults to en when no locale provided", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> Plug.Conn.fetch_query_params()

      conn = SetLocale.call(conn, nil)

      assert conn.assigns.locale == "en"
    end

    test "params take precedence over session", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{locale: "pt_BR"})
        |> Map.put(:params, %{"locale" => "en"})
        |> Plug.Conn.fetch_query_params()

      conn = SetLocale.call(conn, nil)

      assert conn.assigns.locale == "en"
    end
  end
end
