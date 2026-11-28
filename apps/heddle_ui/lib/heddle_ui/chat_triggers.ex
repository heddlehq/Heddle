defmodule HeddleUI.ChatTriggers do
  @moduledoc """
  The published triggers of a workspace that people talk to, like Agents: the nodes
  whose package takes chat messages (see `c:Bobbin.Node.chat_message/4`). The MCP
  tools `list_agents`, `read_agent` and `message_agent` reach them through here, with
  what their package shows in its panel (see `c:Bobbin.Node.panel/2`).
  """

  alias Heddle.Graph
  alias HeddleCore.Accounts.Scope
  alias HeddleCore.Flows
  alias HeddleCore.Flows.Versions
  alias HeddleUI.ChatLive

  @poll 500

  @doc "Each one, with its `name`, the flow it begins and its node."
  def list(%Scope{} = scope) do
    for flow <- Flows.list_flows(scope),
        published = Versions.published_flow(flow),
        published != nil,
        node <- Graph.new(published).nodes,
        module = ChatLive.Show.chat_module(node.type),
        module != nil do
      %{
        name: name(node),
        flow_id: flow.id,
        flow_name: flow.name,
        node_id: node.id,
        type: node.type,
        workspace_id: flow.workspace_id,
        controls: node.controls,
        module: module
      }
    end
    |> Enum.sort_by(& &1.name)
  end

  @doc "The one called `name`, or `{:error, message}`."
  def find(%Scope{} = scope, name) do
    wanted = name |> to_string() |> String.trim() |> String.downcase()

    case Enum.filter(list(scope), &(String.downcase(&1.name) == wanted)) do
      [entry] -> {:ok, entry}
      [] -> {:error, "No published agent is called #{name}. list_agents names them."}
      [_one | _more] -> {:error, "More than one flow is the agent #{name}."}
    end
  end

  @doc "What its package's panel shows, or an empty list."
  def panel(entry) do
    if function_exported?(entry.module, :panel, 2),
      do: entry.module.panel(entry.workspace_id, entry.controls),
      else: []
  end

  @doc """
  Sends `text` in `conversation`, and waits up to `timeout` milliseconds for the
  answer. Returns `{:ok, reply}`, `{:ok, nil}` when none came in time, or
  `{:error, message}`.
  """
  def message(entry, conversation, text, timeout) do
    before = length(history(entry, conversation))

    case entry.module.chat_message(entry.workspace_id, entry.controls, conversation, text) do
      {:ok, _sent} ->
        deadline = System.monotonic_time(:millisecond) + timeout
        {:ok, await_reply(entry, conversation, before + 1, deadline)}

      {:error, message} ->
        {:error, message}
    end
  end

  defp await_reply(entry, conversation, sent, deadline) do
    replies =
      entry
      |> history(conversation)
      |> Enum.drop(sent)
      |> Enum.filter(&(&1.role == :agent))

    cond do
      replies != [] ->
        Enum.map_join(replies, "\n\n", & &1.text)

      System.monotonic_time(:millisecond) >= deadline ->
        nil

      true ->
        Process.sleep(@poll)
        await_reply(entry, conversation, sent, deadline)
    end
  end

  defp history(entry, conversation),
    do: entry.module.chat_history(entry.workspace_id, entry.controls, conversation)

  defp name(node) do
    case String.trim(to_string(node.controls["name"] || "")) do
      "" -> node.label || node.type
      name -> name
    end
  end
end
