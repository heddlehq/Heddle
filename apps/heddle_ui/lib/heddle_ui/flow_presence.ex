defmodule HeddleUI.FlowPresence do
  @moduledoc """
  Who is on a flow's canvas right now, through the channel `"canvas:<id>"`: the people
  who opened it, as many times as they have it open, and the agent while it works on it.

  Each entry, by the `client` of a canvas or `"agent:<user id>"`, has `name`, `color`,
  `kind` (`"person"` or `"agent"`), `user_id`, and what it points at: the nodes
  `selected` and the node `editing` in the drawer. Where cursors are doesn't go here: it
  changes too often, and goes from canvas to canvas, see `HeddleUI.FlowChannel`.
  """

  use Phoenix.Presence, otp_app: :heddle_ui, pubsub_server: HeddleCore.PubSub

  alias HeddleCore.Accounts.User

  # Readable on paper and on ink alike. The agent has a color of its own.
  @colors ~w(#2f7a9e #b5532a #6f5bb0 #2f8a5b #b0367a #8a6d1f #3d6fd1 #a33f3f)
  @agent_color "#7c5cc4"

  def topic(flow_id), do: "canvas:#{flow_id}"

  @doc "The color of a person, the same on every canvas and every visit."
  def color(%User{id: id}), do: Enum.at(@colors, rem(id, length(@colors)))

  def name(%User{username: username}) when is_binary(username) and username != "", do: username
  def name(%User{email: email}), do: email |> String.split("@") |> hd()

  @doc "What a person's canvas says of them."
  def person(%User{} = user) do
    %{
      kind: "person",
      user_id: user.id,
      name: name(user),
      color: color(user),
      selected: [],
      editing: nil
    }
  end

  @doc """
  Shows the agent of `user` on the flow while it works, until `untrack_agent/2`. It runs
  in the process of the conversation, see `HeddleUI.Agent.Session`.
  """
  def track_agent(flow_id, %User{} = user) do
    meta = %{
      kind: "agent",
      user_id: user.id,
      name: name(user),
      color: @agent_color,
      selected: [],
      editing: nil
    }

    case track(self(), topic(flow_id), agent_key(user), meta) do
      {:ok, _ref} -> :ok
      {:error, {:already_tracked, _pid, _topic, _key}} -> :ok
      {:error, _reason} -> :ok
    end
  end

  def untrack_agent(flow_id, %User{} = user) do
    untrack(self(), topic(flow_id), agent_key(user))
  end

  defp agent_key(%User{id: id}), do: "agent:#{id}"
end
