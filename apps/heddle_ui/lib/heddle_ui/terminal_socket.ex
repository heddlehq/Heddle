defmodule HeddleUI.TerminalSocket do
  @moduledoc """
  The connection of the terminal.

  A terminal sends a message for every key and every repaint. Through the LiveView of
  the editor each of those would go through a render of the whole page, and base64 on
  top, so it has a socket of its own, with binary frames.

  It can run commands on this machine, so it checks everything again here: a token only
  says who someone is.
  """

  use Phoenix.Socket

  alias HeddleCore.Accounts
  alias HeddleCore.Accounts.Scope
  alias HeddleUI.Terminal

  channel "terminal:*", HeddleUI.TerminalChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    with true <- Terminal.available?(),
         {:ok, user_id} <- Terminal.verify_token(token),
         %{is_system_admin: true} = user <- Accounts.get_user(user_id) do
      {:ok, assign(socket, :current_scope, Scope.for_user(user))}
    else
      _refused -> :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(_socket), do: nil
end
