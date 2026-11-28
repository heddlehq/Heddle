defmodule HeddleUI.Plugs.IntegrationHookPlug do
  @moduledoc """
  The address services call for the webhook triggers of integrations, `/hooks/:token`
  (see `HeddleCore.Integrations.Hooks`). It runs before `Plug.Parsers`, so the body is
  read as the service sent it: signatures are checked against those exact bytes.

  The manifest checks that the event came from the service and picks its items (see
  `Bobbin.Integration.Webhook`); the published flow starts once per item, from the
  trigger node, with the item as `item`. A service that checks the address first gets
  the answer the manifest gives.
  """

  import Plug.Conn

  alias Heddle.Graph
  alias HeddleCore.{Executions, Flows}
  alias HeddleCore.Flows.Versions
  alias HeddleCore.Integrations.Hooks
  alias HeddleNodes.Manifests

  require Logger

  # Events larger than this are refused: no service sends one, and it would be held in
  # memory to check its signature.
  @max_body 8_000_000
  # So an event with a long list can't start a flood of runs.
  @max_runs 50

  def init(opts), do: opts

  def call(%Plug.Conn{path_info: ["hooks", token]} = conn, _opts) do
    with %{} = hook <- Hooks.get_by_token(token),
         {:ok, body, conn} <- read_all(conn),
         {:ok, flow, node, trigger} <- target(hook),
         {:ok, webhook} <- Hooks.webhook(hook) do
      conn = fetch_query_params(conn)

      event = %{
        headers: Map.new(conn.req_headers),
        body: body,
        query: conn.query_params,
        method: conn.method
      }

      context = Map.merge(node.controls || %{}, %{"workspace_id" => flow.workspace_id})

      case Manifests.receive_webhook(
             trigger.manifest,
             trigger.trigger.name,
             context,
             event,
             webhook
           ) do
        {:reply, status, reply} ->
          conn |> put_resp_content_type("text/plain") |> send_resp(status, reply) |> halt()

        {:ok, items} ->
          started = items |> Enum.take(@max_runs) |> Enum.count(&start(flow, node, &1))
          json(conn, 200, %{received: length(items), started: started})

        {:error, :signature} ->
          json(conn, 401, %{error: "The signature doesn't match"})

        {:error, message} ->
          Logger.warning("#{hook.type} in flow #{flow.id} refused an event: #{message}")
          json(conn, 400, %{error: message})
      end
    else
      {:error, :too_large} -> json(conn, 413, %{error: "The event is too large"})
      {:error, message} when is_binary(message) -> json(conn, 500, %{error: message})
      _not_found -> json(conn, 404, %{error: "Webhook not found"})
    end
  end

  def call(conn, _opts), do: conn

  # The node as the flow publishes it: a hook whose node left the published version is
  # about to be stopped, so it starts nothing.
  defp target(hook) do
    with %{} = flow <- Flows.get_flow(hook.flow_id),
         %{} = published <- Versions.published_flow(flow),
         %Graph.Node{type: type} = node when type == hook.type <-
           Graph.get(Graph.new(published), hook.node_id),
         %{} = trigger <- Manifests.webhook_trigger(type) do
      {:ok, flow, node, trigger}
    else
      _other -> :not_found
    end
  end

  defp start(flow, node, item) do
    input = %{"trigger" => "hook", "node_id" => node.id, "item" => item}

    case Executions.start_execution(flow, input) do
      {:ok, _execution} ->
        true

      {:error, reason} ->
        Logger.error("Could not start flow #{flow.id} for an event: #{inspect(reason)}")
        false
    end
  end

  defp read_all(conn, acc \\ []) do
    case read_body(conn, length: 1_000_000) do
      {:ok, chunk, conn} -> finish([acc, chunk], conn)
      {:more, chunk, conn} -> more([acc, chunk], conn)
      {:error, _reason} -> {:error, :too_large}
    end
  end

  defp more(acc, conn) do
    if IO.iodata_length(acc) > @max_body, do: {:error, :too_large}, else: read_all(conn, acc)
  end

  defp finish(acc, conn) do
    if IO.iodata_length(acc) > @max_body,
      do: {:error, :too_large},
      else: {:ok, IO.iodata_to_binary(acc), conn}
  end

  defp json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
    |> halt()
  end
end
