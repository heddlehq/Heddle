defmodule HeddleUI.PublicAPI.V1.AgentController do
  @moduledoc """
  Talks to the agent of a flow, for clients other than the editor.

  The conversation lives on the server: a client sends messages here and follows
  `events`, a stream of what `HeddleUI.Agent.Transcript` describes.
  """

  use HeddleUI, :controller

  alias HeddleCore.Flows
  alias HeddleUI.Agent
  alias HeddleUI.ApiError
  alias HeddleUI.PublicAPI.V1.AgentEvents

  action_fallback HeddleUI.FallbackController

  plug HeddleUI.Plugs.RequireApiScope, ["workflows:read"] when action in [:show, :events]

  plug HeddleUI.Plugs.RequireApiScope,
       ["workflows:write"] when action in [:message, :decide, :stop, :new_conversation]

  @keep_alive to_timeout(second: 15)

  def show(conn, %{"workflow_id" => id}) do
    with {:ok, flow} <- fetch_flow(conn, id) do
      json(conn, %{data: Agent.transcript(conn.assigns.current_scope, flow.id)})
    end
  end

  def message(conn, %{"workflow_id" => id, "content" => content}) when is_binary(content) do
    with {:ok, flow} <- fetch_flow(conn, id) do
      case Agent.send_message(conn.assigns.current_scope, flow.id, content) do
        :ok -> send_resp(conn, :accepted, "")
        {:error, :busy} -> conflict(conn, "The agent is still working.")
      end
    end
  end

  def decide(conn, %{"workflow_id" => id, "decision" => decision})
      when decision in ["once", "always", "deny"] do
    with {:ok, flow} <- fetch_flow(conn, id) do
      case Agent.decide(conn.assigns.current_scope, flow.id, decision) do
        :ok -> send_resp(conn, :no_content, "")
        {:error, _reason} -> conflict(conn, "Nothing is waiting for an answer.")
      end
    end
  end

  def stop(conn, %{"workflow_id" => id}) do
    with {:ok, flow} <- fetch_flow(conn, id) do
      _result = Agent.stop(conn.assigns.current_scope, flow.id)
      send_resp(conn, :no_content, "")
    end
  end

  @doc "Starts a new conversation, unless the agent is working on the current one."
  def new_conversation(conn, %{"workflow_id" => id}) do
    with {:ok, flow} <- fetch_flow(conn, id) do
      _result = Agent.new_conversation(conn.assigns.current_scope, flow.id)
      send_resp(conn, :no_content, "")
    end
  end

  @doc """
  Streams the conversation as server-sent events, starting with all of it.
  """
  def events(conn, %{"workflow_id" => id}) do
    with {:ok, flow} <- fetch_flow(conn, id) do
      transcript = Agent.join(conn.assigns.current_scope, flow.id)

      conn =
        conn
        |> put_resp_content_type("text/event-stream")
        |> put_resp_header("cache-control", "no-cache")
        |> put_resp_header("x-accel-buffering", "no")
        |> send_chunked(200)

      case chunk(conn, AgentEvents.snapshot(transcript)) do
        {:ok, conn} -> follow(conn)
        {:error, _reason} -> conn
      end
    end
  end

  defp follow(conn) do
    data =
      receive do
        {:agent_event, event} -> AgentEvents.event(event)
      after
        @keep_alive -> AgentEvents.keep_alive()
      end

    case chunk(conn, data) do
      {:ok, conn} -> follow(conn)
      {:error, _reason} -> conn
    end
  end

  defp fetch_flow(conn, id) do
    case Flows.get_flow(conn.assigns.current_scope, id) do
      nil -> {:error, :not_found}
      flow -> {:ok, flow}
    end
  end

  defp conflict(conn, message) do
    conn
    |> put_status(:conflict)
    |> json(ApiError.format(:conflict, message))
  end
end
