defmodule HeddleUI.Plugs.ForceSSLTest do
  use ExUnit.Case, async: false

  import Plug.Test

  alias HeddleUI.Plugs.ForceSSL

  @opts ForceSSL.init(rewrite_on: [:x_forwarded_proto])

  setup do
    on_exit(fn -> Application.delete_env(:heddle_ui, :force_ssl) end)
  end

  defp request(host) do
    :get
    |> conn("/flows")
    |> Map.put(:host, host)
    |> ForceSSL.call(@opts)
  end

  test "leaves plain HTTP alone by default" do
    conn = request("192.168.1.50")

    refute conn.halted
    assert conn.status == nil
  end

  test "redirects to HTTPS on the requested host when enabled" do
    Application.put_env(:heddle_ui, :force_ssl, true)

    conn = request("heddle.example.com")

    assert conn.halted
    assert conn.status == 301
    assert Plug.Conn.get_resp_header(conn, "location") == ["https://heddle.example.com/flows"]
  end

  test "trusts x-forwarded-proto from the TLS proxy when enabled" do
    Application.put_env(:heddle_ui, :force_ssl, true)

    conn =
      :get
      |> conn("/flows")
      |> Map.put(:host, "heddle.example.com")
      |> Plug.Conn.put_req_header("x-forwarded-proto", "https")
      |> ForceSSL.call(@opts)

    refute conn.halted
  end
end
