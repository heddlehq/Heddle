defmodule HeddleUI.Plugs.WebhookPlug do
  @moduledoc """
  Plug that intercepts incoming HTTP requests matching `/api/flows/:id/webhook/*` paths
  and routes them to the appropriate flow execution.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(%Plug.Conn{path_info: ["api", "flows", flow_id, "webhook" | rest]} = conn, _opts)
      when rest != [] do
    slug = Enum.join(rest, "/")

    case HeddleCore.Webhooks.get_by_flow_and_slug(flow_id, slug) do
      {:ok, %{method: expected_method}} ->
        if String.upcase(conn.method) == String.upcase(expected_method) do
          execute_webhook(conn, flow_id)
        else
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(
            405,
            Jason.encode!(%{error: "Method not allowed. Expected #{expected_method}"})
          )
          |> halt()
        end

      :error ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "Webhook not found"}))
        |> halt()
    end
  end

  def call(conn, _opts), do: conn

  # A webhook runs what the flow publishes, never its draft. See
  # `HeddleCore.Flows.Versions`.
  defp execute_webhook(conn, flow_id) do
    flow =
      case HeddleCore.Flows.Cache.get(flow_id) do
        nil ->
          flow =
            flow_id |> HeddleCore.Flows.get_flow!() |> HeddleCore.Flows.Versions.published_flow()

          if flow, do: HeddleCore.Flows.Cache.put(flow)
          flow

        cached ->
          cached
      end

    if flow, do: run_webhook(conn, flow), else: not_found(conn)
  rescue
    Ecto.NoResultsError -> not_found(conn)
  end

  defp not_found(conn) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(404, Jason.encode!(%{error: "Flow not found"}))
    |> halt()
  end

  defp run_webhook(conn, flow) do
    with {:ok, execution} <- create_webhook_execution(flow, conn),
         {:ok, _job} <- HeddleCore.Executions.enqueue_execution(execution) do
      if responds?(flow) do
        respond_from_flow(conn, execution)
      else
        send_accepted(conn, execution)
      end
    else
      {:error, _reason} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(500, Jason.encode!(%{error: "Execution could not be queued"}))
        |> halt()
    end
  end

  defp responds?(flow) do
    flow |> Heddle.Graph.new() |> Heddle.Graph.of_type("Respond to Webhook") != []
  end

  defp respond_from_flow(conn, execution) do
    case HeddleCore.Executions.await_response(execution, await_options()) do
      {:ok, response} ->
        conn
        |> put_resp_content_type(response["content_type"])
        |> send_resp(response["status"], response["body"])
        |> halt()

      {:error, :no_response} ->
        send_accepted(conn, execution)

      {:error, :failed} ->
        send_error(conn, 500, "The flow failed before responding", execution)

      {:error, :timeout} ->
        send_error(conn, 504, "The flow did not respond in time", execution)
    end
  end

  defp await_options, do: Application.get_env(:heddle_ui, :webhook_response, [])

  defp send_accepted(conn, execution) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(
      202,
      Jason.encode!(%{
        status: "accepted",
        execution_id: execution.public_id,
        execution_status: execution.status
      })
    )
    |> halt()
  end

  defp send_error(conn, status, message, execution) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(%{error: message, execution_id: execution.public_id}))
    |> halt()
  end

  defp create_webhook_execution(flow, conn) do
    HeddleCore.Executions.create_execution(%{
      flow_id: flow.id,
      flow_version_id: flow.published_version_id,
      input: %{
        "trigger" => "webhook",
        "request" => %{
          "body" => conn.body_params,
          "headers" => Enum.into(conn.req_headers, %{}),
          "method" => conn.method,
          "query_params" => conn.query_params,
          "path" => conn.request_path
        }
      }
    })
  end
end
