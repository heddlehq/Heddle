defmodule HeddleUI.Plugs.ChatVisitor do
  @moduledoc """
  Gives a browser that opens a public chat an id of its own, kept in its session, so
  each visitor is a conversation of their own. See `HeddleUI.ChatLive.Show`.
  """

  import Plug.Conn

  def init(options), do: options

  def call(conn, _options) do
    case get_session(conn, :chat_visitor) do
      id when is_binary(id) ->
        conn

      _none ->
        put_session(
          conn,
          :chat_visitor,
          Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
        )
    end
  end

  @doc "What the chat's LiveView gets from the session: the visitor and the language."
  def live_session(conn) do
    %{"chat_visitor" => get_session(conn, :chat_visitor), "locale" => get_session(conn, :locale)}
  end
end
