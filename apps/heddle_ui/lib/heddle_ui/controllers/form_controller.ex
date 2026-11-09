defmodule HeddleUI.FormController do
  @moduledoc """
  The page of a Form Trigger, at `/f/:token`, which anyone with the link can fill in,
  and its test, at `/flows/:id/forms/:node_id/test`, for people who can run the flow.

  The public page shows what is published and runs the published version. It is
  plain HTML, so it works without JavaScript, and follows the visitor's language and
  theme. A hidden field that people never see catches bots, and each address can send
  a form only so many times a minute (`HeddleUI.FormRateLimit`). See
  `HeddleCore.Forms`.
  """

  use HeddleUI, :controller

  alias HeddleCore.{Flows, Forms}

  # Bots fill in every field. People never see this one.
  @honeypot "website"

  plug :put_layout, false
  plug :put_view, HeddleUI.FormHTML

  def show(conn, %{"token" => token}) do
    conn = public(conn)

    case Forms.public(token) do
      {:ok, page} -> render_form(conn, page, action: ~p"/f/#{token}")
      {:error, :closed, page} -> render(conn, :closed, page: page)
      {:error, :not_found} -> not_found(conn)
    end
  end

  def submit(conn, %{"token" => token} = params) do
    conn = public(conn)
    values = params["form"] || %{}

    cond do
      params[@honeypot] not in [nil, ""] ->
        pretend_sent(conn, token)

      not HeddleUI.FormRateLimit.allow?({client_ip(conn), token}) ->
        case Forms.public(token) do
          {:ok, page} ->
            conn
            |> put_status(:too_many_requests)
            |> render_form(page,
              action: ~p"/f/#{token}",
              values: values,
              alert:
                gettext("You sent this form many times in a row. Wait a minute and try again.")
            )

          _other ->
            not_found(conn)
        end

      true ->
        case Forms.submit(token, values, answer_options()) do
          {:ok, page} ->
            sent(conn, page)

          {:error, :invalid, page, errors, values} ->
            conn
            |> put_status(:unprocessable_entity)
            |> render_form(page, action: ~p"/f/#{token}", values: values, errors: errors)

          {:error, :rejected, page, issues, values} ->
            rejected(conn, page, issues, values, action: ~p"/f/#{token}")

          {:error, :closed, page} ->
            render(conn, :closed, page: page)

          {:error, :not_started, page} ->
            conn
            |> put_status(:service_unavailable)
            |> render_form(page,
              action: ~p"/f/#{token}",
              values: values,
              alert: gettext("Your answers couldn't be sent now. Please try again.")
            )

          {:error, :not_found} ->
            not_found(conn)
        end
    end
  end

  def test(conn, %{"id" => id, "node_id" => node_id}) do
    with_flow(conn, id, fn flow ->
      case Forms.draft(conn.assigns.current_scope, flow, node_id) do
        {:ok, page} ->
          render_form(conn, page, action: ~p"/flows/#{flow.id}/forms/#{node_id}/test", test: flow)

        {:error, :forbidden} ->
          forbidden(conn)

        {:error, :not_found} ->
          not_found(conn)
      end
    end)
  end

  def submit_test(conn, %{"id" => id, "node_id" => node_id} = params) do
    with_flow(conn, id, fn flow ->
      action = ~p"/flows/#{flow.id}/forms/#{node_id}/test"

      case Forms.submit_draft(
             conn.assigns.current_scope,
             flow,
             node_id,
             params["form"] || %{},
             answer_options()
           ) do
        {:ok, execution, page} ->
          render(conn, :sent, page: page, test: flow, execution: execution)

        {:error, :invalid, page, errors, values} ->
          conn
          |> put_status(:unprocessable_entity)
          |> render_form(page, action: action, values: values, errors: errors, test: flow)

        {:error, :rejected, page, issues, values} ->
          rejected(conn, page, issues, values, action: action, test: flow)

        {:error, :forbidden} ->
          forbidden(conn)

        {:error, :not_found} ->
          not_found(conn)

        {:error, _reason} ->
          conn
          |> put_flash(:error, gettext("The flow could not be started."))
          |> redirect(to: action)
      end
    end)
  end

  defp with_flow(conn, id, fun) do
    case Flows.get_flow(conn.assigns.current_scope, id) do
      nil -> not_found(conn)
      flow -> fun.(flow)
    end
  end

  defp render_form(conn, page, opts) do
    render(conn, :show,
      page: page,
      action: Keyword.fetch!(opts, :action),
      values: Keyword.get(opts, :values, %{}),
      errors: Keyword.get(opts, :errors, %{}),
      alert: Keyword.get(opts, :alert),
      test: Keyword.get(opts, :test),
      honeypot: @honeypot
    )
  end

  # A Validate of the flow refused what was sent: each error goes by its field, and
  # the rest above the form. See `HeddleUI.SchemaErrors`.
  defp rejected(conn, page, issues, values, opts) do
    {errors, others} = HeddleUI.SchemaErrors.by_field(issues, page.fields)
    alert = if others == [], do: nil, else: Enum.join(others, " ")

    conn
    |> put_status(:unprocessable_entity)
    |> render_form(page, [values: values, errors: errors, alert: alert] ++ opts)
  end

  # How long sending waits for a Validate of the flow to answer.
  defp answer_options, do: Application.get_env(:heddle_ui, :form_answer, [])

  defp sent(conn, %{redirect_url: url}) when is_binary(url), do: redirect(conn, external: url)
  defp sent(conn, page), do: render(conn, :sent, page: page, test: nil, execution: nil)

  # A bot is told it worked, so it has no reason to try again.
  defp pretend_sent(conn, token) do
    case Forms.public(token) do
      {:ok, page} ->
        render(conn, :sent, page: %{page | redirect_url: nil}, test: nil, execution: nil)

      _other ->
        not_found(conn)
    end
  end

  defp not_found(conn) do
    conn |> public() |> put_status(:not_found) |> render(:not_found)
  end

  defp forbidden(conn) do
    conn |> put_status(:forbidden) |> render(:forbidden)
  end

  # The page follows the device of whoever opens it, see the root layout.
  defp public(conn), do: assign(conn, :theme_lock, "system")

  defp client_ip(conn), do: conn.remote_ip |> :inet.ntoa() |> to_string()
end
