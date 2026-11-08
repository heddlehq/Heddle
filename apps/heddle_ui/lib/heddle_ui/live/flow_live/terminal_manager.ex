defmodule HeddleUI.FlowLive.TerminalManager do
  @moduledoc """
  Socket reducers for the panel of the terminal inside `FlowLive`. What runs in it goes
  through `HeddleUI.TerminalChannel`, away from this LiveView.
  """

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [push_event: 3]

  alias HeddleUI.Terminal

  @doc "Default terminal-related assigns, merged into the LiveView mount."
  # Claude Code runs on the server with its access, so only system admins get it, and
  # it changes the flow, so only when they can edit it.
  def initial_assigns(user, can_edit) do
    available? =
      can_edit and HeddleCore.Accounts.User.system_admin?(user) and Terminal.available?()

    [
      terminal_available: available?,
      terminal_token: if(available?, do: Terminal.token(user)),
      terminal_open: false,
      terminal_exited: false
    ]
  end

  def toggle(socket), do: assign(socket, terminal_open: not socket.assigns.terminal_open)

  def exited(socket), do: assign(socket, terminal_exited: true)

  def restart(socket) do
    socket
    |> assign(terminal_exited: false)
    |> push_event("terminal_restart", %{})
  end
end
