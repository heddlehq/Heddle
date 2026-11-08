defmodule HeddleUI.PublicAPI.V1.LiveController do
  @moduledoc """
  Editing a workflow together with others, for clients other than the canvas: `live`
  follows it as server-sent events (see `HeddleUI.PublicAPI.V1.LiveFlow`), `changes`
  changes it, and `focus` says which nodes the person points at.

  `PUT /workflows/:id` makes the draft the graph it is given, which takes back whatever
  someone else changed since the client read it. `changes` with `base`, the graph the
  client last had, applies only what the client changed since then (see
  `Heddle.Graph.Ops.between/2`), on top of what everyone else did meanwhile.
  """

  use HeddleUI, :controller

  alias Heddle.Graph.Ops
  alias HeddleCore.ApiKeys.ApiKey
  alias HeddleCore.Flows
  alias HeddleUI.ApiError
  alias HeddleUI.PublicAPI.V1.LiveFlow

  action_fallback HeddleUI.FallbackController

  plug HeddleUI.Plugs.RequireApiScope, ["workflows:read"] when action in [:live, :focus]
  plug HeddleUI.Plugs.RequireApiScope, ["workflows:write"] when action in [:changes]

  # The route of `live` takes any Accept, for the event stream, so its errors need one.
  plug :put_format, "json" when action == :live

  @keep_alive to_timeout(second: 15)

  def live(conn, %{"workflow_id" => id}) do
    scope = conn.assigns.current_scope
    can_write = ApiKey.allows?(conn.assigns.api_key, ["workflows:write"])

    with {:ok, state, events} <- LiveFlow.start(scope, id, can_write: can_write) do
      conn =
        conn
        |> put_resp_content_type("text/event-stream")
        |> put_resp_header("cache-control", "no-cache")
        |> put_resp_header("x-accel-buffering", "no")
        |> send_chunked(200)

      {conn, state} =
        case write(conn, events) do
          {:ok, conn} -> follow(conn, state)
          {:error, conn} -> {conn, state}
        end

      LiveFlow.stop(state)
      conn
    end
  end

  def changes(conn, %{"workflow_id" => id} = params) do
    scope = conn.assigns.current_scope
    meta = %{client: string(params["client"]), ref: params["ref"]}

    with {:ok, ops} <- operations(params) do
      result =
        if ops == [],
          do: Flows.session_snapshot(scope, :edit, id),
          else: apply_ops(scope, id, ops, meta)

      case result do
        {:ok, _flow, snapshot} ->
          json(conn, %{
            data: %{
              seq: snapshot.seq,
              applied: snapshot[:applied],
              graph: LiveFlow.render_graph(snapshot.graph)
            }
          })

        {:error, reason} when reason in [:not_found, :forbidden] ->
          {:error, reason}

        {:error, reason} ->
          conn
          |> put_status(:conflict)
          |> json(ApiError.format(:conflict, conflict_message(reason)))
      end
    else
      {:error, :invalid} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(
          ApiError.format(
            :invalid_request,
            "Send either ops, a list of operations, or base and graph, two graphs."
          )
        )
    end
  end

  def focus(conn, %{"workflow_id" => id} = params) do
    case LiveFlow.focus(conn.assigns.current_scope, id, params["client"], params) do
      :ok -> send_resp(conn, :no_content, "")
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  defp follow(conn, state) do
    {events, state, continue?} =
      receive do
        message ->
          case LiveFlow.handle(message, state) do
            {:ok, events, state} -> {events, state, true}
            {:stop, events, state} -> {events, state, false}
          end
      after
        @keep_alive -> {[LiveFlow.keep_alive()], state, true}
      end

    case write(conn, events) do
      {:ok, conn} when continue? -> follow(conn, state)
      {_result, conn} -> {conn, state}
    end
  end

  defp write(conn, []), do: {:ok, conn}

  defp write(conn, events) do
    case chunk(conn, events) do
      {:ok, conn} -> {:ok, conn}
      {:error, _reason} -> {:error, conn}
    end
  end

  defp apply_ops(scope, id, ops, meta) do
    with {:ok, seq} <- Flows.apply_operations(scope, id, ops, meta),
         {:ok, flow, snapshot} <- Flows.session_snapshot(scope, :view, id) do
      {:ok, flow, Map.put(snapshot, :applied, seq)}
    end
  end

  defp operations(%{"ops" => ops}) when is_list(ops) do
    if Enum.all?(ops, &is_map/1), do: {:ok, ops}, else: {:error, :invalid}
  end

  defp operations(%{"base" => base, "graph" => graph}) do
    if graph?(base) and graph?(graph),
      do: {:ok, Ops.between(base, graph)},
      else: {:error, :invalid}
  end

  defp operations(_params), do: {:error, :invalid}

  # What `Ops.between/2` can read: lists of maps, each node and comment with an id.
  defp graph?(graph) when is_map(graph) do
    Enum.all?(["nodes", "comments"], &items?(graph[&1], true)) and
      items?(graph["connections"], false)
  end

  defp graph?(_graph), do: false

  defp items?(nil, _id?), do: true

  defp items?(items, id?) when is_list(items) do
    Enum.all?(items, fn item ->
      is_map(item) and (not id? or is_binary(item["id"]) or is_integer(item["id"]))
    end)
  end

  defp items?(_items, _id?), do: false

  defp conflict_message(reason) when is_binary(reason),
    do: "The workflow changed and these operations no longer apply: #{reason}"

  defp conflict_message(_reason), do: "The workflow changed and these operations no longer apply."

  defp string(value) when is_binary(value), do: value
  defp string(_value), do: nil
end
