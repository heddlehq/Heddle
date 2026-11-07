defmodule HeddleUI.Terminal do
  @moduledoc """
  Claude Code in a terminal of the editor, for who installed Heddle on their own machine.

  It is the program as Anthropic ships it, run with no changes, and whoever uses it signs
  in through its own flow, with their own account or API key. Anthropic allows that, and
  not Heddle offering that sign-in or sending requests through a subscription, so Heddle
  never touches the login and never reads what the terminal shows: it only carries the
  keys and the screen. The terms also keep the name out of ours: this is the Terminal,
  which runs Claude Code.

  It gives whoever opens it a shell-capable agent on this machine, so it only exists on
  a local install, starts turned off in the AI page, and is limited to administrators.
  """

  alias HeddleAI.ClaudeAgent
  alias HeddleCore.Accounts.User
  alias HeddleCore.Flows.Flow
  alias HeddleCore.Settings
  alias HeddleUI.Terminal.Session

  @token_salt "terminal"
  @token_max_age to_timeout(hour: 12) |> div(1000)

  @doc "Whether this install can offer the terminal, which a person still has to turn on."
  def supported? do
    Application.get_env(:heddle_ui, :terminal, false) and Code.ensure_loaded?(:exec) and
      command() != nil
  end

  @doc "Whether the editor shows the terminal."
  def available?, do: supported?() and Settings.terminal_enabled?()

  @doc "A token for the connection of the terminal, which doesn't carry a session."
  def token(%User{id: id}), do: Phoenix.Token.sign(HeddleUI.Endpoint, @token_salt, id)

  @doc "Returns the user id of a token."
  def verify_token(token) do
    Phoenix.Token.verify(HeddleUI.Endpoint, @token_salt, token, max_age: @token_max_age)
  end

  @doc """
  Opens a terminal for the calling process, which it follows: it ends with the caller.

  The caller receives `{:terminal_output, data}` and then `:terminal_exited`.
  """
  def open(scope, %Flow{} = flow, {cols, rows}) do
    opts = [owner: self(), scope: scope, flow: flow, size: {cols, rows}]

    DynamicSupervisor.start_child(HeddleUI.Agent.supervisor(), {Session, opts})
  end

  def input(terminal, data), do: Session.input(terminal, data)

  def resize(terminal, cols, rows), do: Session.resize(terminal, cols, rows)

  @doc "What runs in the terminal, as a list with the path of the program first."
  def command do
    case Application.get_env(:heddle_ui, :terminal_command) do
      nil -> claude()
      command -> command
    end
  end

  defp claude do
    case ClaudeAgent.status().binary do
      nil -> nil
      path -> [path]
    end
  end
end
