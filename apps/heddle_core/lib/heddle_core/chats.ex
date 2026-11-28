defmodule HeddleCore.Chats do
  @moduledoc """
  Chat pages anyone with the link can talk on, each one a trigger of a flow whose
  node takes chat messages, like a package's Agent (see `c:Bobbin.Node.chat_message/4`).

  Like a form's (see `HeddleCore.Forms`), the link lives in a `HeddleCore.Chats.Chat`,
  made the first time someone looks for it, and stays the same across publishes until
  an editor makes a new one. It talks to what is published: a flow never published,
  or whose published version doesn't have the node, has no chat there.

  Which nodes take chat messages is for the app that runs them to say, so this module
  takes any node.
  """

  alias Heddle.Graph
  alias HeddleCore.Accounts.Scope
  alias HeddleCore.Chats.Chat
  alias HeddleCore.{Flows, Repo, Workspaces}
  alias HeddleCore.Flows.{Flow, Versions}

  @doc """
  The chat of the node `node_id` in the draft of `flow`, which the caller can see.
  Makes it the first time. Returns `{:ok, chat}` or `{:error, :not_found | :forbidden}`.
  """
  def link(%Scope{} = scope, %Flow{} = flow, node_id) do
    with :ok <- Workspaces.authorize(scope, :view, flow.workspace_id),
         %Graph.Node{} <- flow |> Graph.new() |> Graph.get(to_string(node_id)) do
      {:ok, ensure(flow.id, to_string(node_id))}
    else
      {:error, :forbidden} -> {:error, :forbidden}
      _other -> {:error, :not_found}
    end
  end

  defp ensure(flow_id, node_id) do
    now = DateTime.utc_now(:second)

    Repo.insert_all(
      Chat,
      [
        %{
          flow_id: flow_id,
          node_id: node_id,
          token: Chat.new_token(),
          inserted_at: now,
          updated_at: now
        }
      ],
      on_conflict: :nothing,
      conflict_target: [:flow_id, :node_id]
    )

    Repo.get_by!(Chat, flow_id: flow_id, node_id: node_id)
  end

  @doc "Gives a chat a new link, so the old one stops working. Editors and up."
  def regenerate(%Scope{} = scope, %Flow{} = flow, node_id) do
    with :ok <- Workspaces.authorize(scope, :edit, flow.workspace_id),
         {:ok, chat} <- link(scope, flow, node_id) do
      chat |> Ecto.Changeset.change(token: Chat.new_token()) |> Repo.update()
    end
  end

  @doc """
  The chat published at `token`: `{:ok, %{workspace_id, flow, node}}` with the node as
  the published version has it, or `{:error, :not_found}`.
  """
  def published(token) when is_binary(token) do
    with %Chat{} = chat <- Repo.get_by(Chat, token: token),
         %Flow{} = flow <- Repo.get(Flow, chat.flow_id),
         %{} = published <- Versions.published_flow(flow),
         %Graph.Node{} = node <- published |> Graph.new() |> Graph.get(chat.node_id) do
      {:ok, %{workspace_id: flow.workspace_id, flow: published, node: node}}
    else
      _other -> {:error, :not_found}
    end
  end

  def published(_token), do: {:error, :not_found}

  @doc """
  The node `node_id` of the published version of the flow `flow_id`, for someone who
  can run it, to try its chat from the editor. Same answers as `published/1`, and
  `{:error, :not_published}` when the published version doesn't have it.
  """
  def for_test(%Scope{} = scope, flow_id, node_id) do
    with %Flow{} = flow <- Flows.get_flow(scope, flow_id) || {:error, :not_found},
         :ok <- Workspaces.authorize(scope, :run, flow.workspace_id),
         %{} = published <- Versions.published_flow(flow) || {:error, :not_published},
         %Graph.Node{} = node <-
           published |> Graph.new() |> Graph.get(to_string(node_id)) || {:error, :not_published} do
      {:ok, %{workspace_id: flow.workspace_id, flow: published, node: node}}
    end
  end
end
