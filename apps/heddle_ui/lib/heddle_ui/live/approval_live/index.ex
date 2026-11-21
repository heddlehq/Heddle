defmodule HeddleUI.ApprovalLive.Index do
  @moduledoc """
  The runs of the workspace that wait at an Approval node, for a person to approve or
  reject. Viewers see them, and people who can run flows decide. See
  `HeddleCore.Executions.decide/4`.
  """

  use HeddleUI, :live_view

  on_mount {HeddleUI.UserAuth, {:require_workspace, :view}}

  alias HeddleCore.{Executions, Workspaces}

  # Runs reach an Approval from the worker, which tells no page, so it looks again.
  @refresh :timer.seconds(5)

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(@refresh, :refresh)

    {:ok,
     socket
     |> assign(:page_title, gettext("Approvals"))
     |> assign(:can_decide, Workspaces.can?(socket.assigns.current_scope, :run))
     |> assign(:comments, %{})
     |> load()}
  end

  defp load(socket) do
    assign(socket, :approvals, Executions.list_approvals(socket.assigns.current_scope))
  end

  @impl true
  def handle_info(:refresh, socket), do: {:noreply, load(socket)}

  @impl true
  def handle_event("comment", %{"execution" => id, "comment" => comment}, socket) do
    {:noreply, update(socket, :comments, &Map.put(&1, id, comment))}
  end

  def handle_event("decide", %{"id" => id, "decision" => decision}, socket)
      when decision in ["approved", "rejected"] do
    comment = socket.assigns.comments[id]

    socket =
      case Executions.decide(socket.assigns.current_scope, id, decision, comment) do
        {:ok, _execution} ->
          message =
            if decision == "approved",
              do: gettext("Approved. The run goes on."),
              else: gettext("Rejected. The run goes on through rejected.")

          socket
          |> put_flash(:info, message)
          |> update(:comments, &Map.delete(&1, id))
          |> update(:approvals, fn approvals -> Enum.reject(approvals, &(&1.id == id)) end)

        {:error, :forbidden} ->
          put_flash(socket, :error, gettext("Your role lets you see approvals, not decide them."))

        {:error, :already_resumed} ->
          put_flash(socket, :error, gettext("Someone else decided this one first."))

        {:error, _reason} ->
          socket
          |> put_flash(:error, gettext("This run isn't waiting for an approval anymore."))
          |> load()
      end

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 md:p-8 w-full max-w-4xl mx-auto space-y-8">
      <div>
        <h1 class="flex items-center gap-2 text-2xl font-bold text-gray-900 dark:text-white">
          <.icon name="hero-hand-raised" class="size-6 text-primary" /> {gettext("Approvals")}
        </h1>
        <p class="mt-1 max-w-2xl text-sm text-gray-500 dark:text-gray-400">
          {gettext(
            "Runs that stopped at an Approval node and wait for someone to decide. Each one goes on through approved or rejected, and keeps who decided and why."
          )}
        </p>
      </div>

      <div
        :if={@approvals == []}
        id="approvals-empty"
        class="flex flex-col items-center gap-3 rounded-xl border border-dashed border-gray-300 px-6 py-16 text-center dark:border-slate-700"
      >
        <span class="flex size-12 items-center justify-center rounded-full bg-primary/10 text-primary">
          <.icon name="hero-check-badge" class="size-6" />
        </span>
        <p class="text-sm font-medium text-gray-900 dark:text-white">
          {gettext("Nothing waits for you")}
        </p>
        <p class="max-w-sm text-sm text-gray-500 dark:text-gray-400">
          {gettext(
            "Put an Approval node in a flow where a person must say yes first, like before paying a refund. Its runs show up here."
          )}
        </p>
      </div>

      <ul id="approvals" class="space-y-4">
        <li
          :for={execution <- @approvals}
          id={"approval-#{execution.id}"}
          class="rounded-xl border border-gray-200 bg-white p-5 shadow-sm dark:border-slate-800 dark:bg-slate-900"
        >
          <div class="flex flex-wrap items-start justify-between gap-2">
            <div class="min-w-0">
              <p class="font-semibold text-gray-900 dark:text-white">
                {approval(execution)["title"]}
              </p>
              <p class="mt-0.5 text-xs text-gray-500 dark:text-gray-400">
                <.link navigate={~p"/flows/#{execution.flow_id}"} class="hover:underline">
                  {execution.flow.name}
                </.link>
                ·
                <.link
                  navigate={~p"/executions/#{execution.public_id}"}
                  class="font-mono hover:underline"
                >
                  {execution.public_id}
                </.link>
                · {gettext("waiting since %{time}", time: since(execution))}
              </p>
            </div>
            <span
              :if={deadline(execution)}
              class="rounded-md bg-amber-500/15 px-2 py-0.5 text-xs text-amber-700 dark:text-amber-300"
            >
              {gettext("Times out %{time}", time: deadline(execution))}
            </span>
          </div>

          <p
            :if={approval(execution)["details"] not in [nil, ""]}
            class="mt-3 whitespace-pre-line text-sm text-gray-700 dark:text-gray-300"
          >
            {approval(execution)["details"]}
          </p>

          <form
            :if={@can_decide}
            id={"approval-form-#{execution.id}"}
            phx-change="comment"
            class="mt-4 flex flex-col gap-2 sm:flex-row sm:items-center"
          >
            <input type="hidden" name="execution" value={execution.id} />
            <input
              type="text"
              name="comment"
              value={@comments[execution.id]}
              placeholder={gettext("Comment, if you want")}
              autocomplete="off"
              class="min-w-0 flex-1 rounded-lg border border-gray-200 bg-gray-50 px-3 py-2 text-sm text-gray-900 focus:border-primary focus:outline-none focus:ring-2 focus:ring-primary/20 dark:border-slate-700 dark:bg-slate-800 dark:text-gray-100"
            />
            <div class="flex gap-2">
              <.button
                id={"approve-#{execution.id}"}
                type="button"
                variant="primary"
                phx-click="decide"
                phx-value-id={execution.id}
                phx-value-decision="approved"
              >
                <.icon name="hero-check" class="size-4" /> {gettext("Approve")}
              </.button>
              <.button
                id={"reject-#{execution.id}"}
                type="button"
                phx-click="decide"
                phx-value-id={execution.id}
                phx-value-decision="rejected"
              >
                <.icon name="hero-x-mark" class="size-4" /> {gettext("Reject")}
              </.button>
            </div>
          </form>
        </li>
      </ul>
    </div>
    """
  end

  defp approval(execution), do: get_in(execution.paused, ["wait", "approval"]) || %{}

  defp since(execution), do: Calendar.strftime(execution.updated_at, "%Y-%m-%d %H:%M UTC")

  defp deadline(execution) do
    with at when is_binary(at) <- get_in(execution.paused, ["wait", "resume_at"]),
         {:ok, at, _offset} <- DateTime.from_iso8601(at) do
      Calendar.strftime(at, "%Y-%m-%d %H:%M UTC")
    else
      _none -> nil
    end
  end
end
