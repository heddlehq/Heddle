defmodule HeddleUI.Plugs.ForceSSL do
  @moduledoc """
  Runs `Plug.SSL` only when `config :heddle_ui, :force_ssl` is true.

  The endpoint's own `:force_ssl` option is fixed at compile time, which would
  send a self-hosted install on a plain IP to an HTTPS address that doesn't
  exist. `config/runtime.exs` turns this on once `PHX_HOST` names a public domain.
  """

  @behaviour Plug

  @impl true
  def init(opts), do: Plug.SSL.init(opts)

  @impl true
  def call(conn, opts) do
    if Application.get_env(:heddle_ui, :force_ssl, false) do
      Plug.SSL.call(conn, opts)
    else
      conn
    end
  end
end
