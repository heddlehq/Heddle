defmodule HeddleUI.Plugs.ResumePlug do
  @moduledoc """
  Resumes a run at a Wait that waits for a call, at `/api/resume/:token`.

  It takes any method, so a link in an email works as well as a call from another
  service. The Wait passes on the body, the query string and the method as its
  `result`. The token is the only secret, as the slug of a webhook is.
  """

  import Plug.Conn

  alias HeddleCore.Executions

  def init(opts), do: opts

  def call(%Plug.Conn{path_info: ["api", "resume", token]} = conn, _opts) do
    request = %{
      "body" => conn.body_params,
      "query_params" => conn.query_params,
      "method" => conn.method
    }

    case Executions.resume_by_call(token, request, resume_options()) do
      {:ok, execution} ->
        reply(conn, 202, %{status: "resumed", execution_id: execution.public_id})

      {:error, :not_found} ->
        reply(conn, 404, %{error: "No run waits at this address."})

      {:error, :already_resumed} ->
        reply(conn, 409, %{error: "This run was already resumed."})

      {:error, :not_waiting} ->
        reply(conn, 409, %{error: "This run isn't waiting for a call now."})

      {:error, :finished} ->
        reply(conn, 410, %{error: "This run has already finished."})

      {:error, _reason} ->
        reply(conn, 500, %{error: "The run could not be resumed."})
    end
  end

  def call(conn, _opts), do: conn

  defp resume_options, do: Application.get_env(:heddle_ui, :resume_call, [])

  defp reply(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
    |> halt()
  end
end
