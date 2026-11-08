defmodule HeddleUI.FlowSocket do
  @moduledoc """
  The connection a canvas edits a flow through, with others. It is apart from the
  LiveView of the editor because every change and, later, every move of a cursor goes
  through it: through the LiveView, each would render the page.

  A token only says who someone is. What they may do with a flow is checked again on
  each join and each change, see `HeddleUI.FlowChannel`.
  """

  use Phoenix.Socket

  alias HeddleCore.Accounts
  alias HeddleCore.Accounts.Scope
  alias HeddleCore.Accounts.User

  @salt "flow socket"
  @max_age to_timeout(day: 1) |> div(1000)

  channel "flow:*", HeddleUI.FlowChannel

  @doc "The token a canvas connects with, for `user`."
  def token(%User{id: id}), do: Phoenix.Token.sign(HeddleUI.Endpoint, @salt, id)

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    with {:ok, user_id} <-
           Phoenix.Token.verify(HeddleUI.Endpoint, @salt, token, max_age: @max_age),
         %User{} = user <- Accounts.get_user(user_id) do
      {:ok, assign(socket, :current_scope, Scope.for_user(user))}
    else
      _refused -> :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(%{assigns: %{current_scope: %{user: user}}}), do: "flow_socket:#{user.id}"
end
