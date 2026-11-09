defmodule HeddleUI.DashboardLive.Index do
  use HeddleUI, :live_view

  import HeddleUI.Components.Dashboard

  alias HeddleCore.Accounts.Scope
  alias HeddleCore.Executions
  alias HeddleCore.Workspaces

  @days 14
  # The runs go on while someone looks, so the figures follow them.
  @refresh to_timeout(second: 15)

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    in_workspace? = not is_nil(scope.workspace)

    if connected?(socket) and in_workspace?, do: schedule_refresh()

    {:ok,
     socket
     |> assign(
       page_title: gettext("Dashboard"),
       days: @days,
       in_workspace?: in_workspace?,
       can_edit?: Workspaces.can?(scope, :edit),
       system_admin?: Scope.system_admin?(scope)
     )
     |> load()}
  end

  @impl true
  def handle_info(:refresh, socket) do
    schedule_refresh()
    {:noreply, load(socket)}
  end

  defp schedule_refresh, do: Process.send_after(self(), :refresh, @refresh)

  defp load(socket) do
    now = DateTime.utc_now(:second)
    overview = Executions.overview(socket.assigns.current_scope, days: @days, now: now)
    assign(socket, overview: overview, now: now)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="w-full bg-gray-50 dark:bg-slate-950">
      <div class="mx-auto w-full max-w-7xl p-6 md:p-8">
        <header class="mb-8 flex flex-col gap-4 md:flex-row md:items-end md:justify-between">
          <div class="min-w-0">
            <p
              :if={@in_workspace?}
              class="mb-1 flex items-center gap-1.5 text-xs font-medium uppercase tracking-wider text-gray-500 dark:text-gray-400"
            >
              <.icon name="hero-building-office-2-micro" class="size-3.5" />
              {@current_scope.workspace.name}
            </p>
            <h1 class="text-2xl font-bold tracking-tight text-gray-900 dark:text-white">
              {gettext("Dashboard")}
            </h1>
            <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
              <%= if @in_workspace? do %>
                {gettext("How your flows ran in the last %{count} days.", count: @days)}
              <% else %>
                {gettext("You aren't in a workspace yet. Ask an admin to add you to one.")}
              <% end %>
            </p>
          </div>

          <div :if={@in_workspace?} class="flex flex-wrap items-center gap-2">
            <.live_now active={@overview.active} />
            <.button id="dashboard-executions" navigate={~p"/executions"} variant="ghost">
              <.icon name="hero-queue-list" class="size-4" /> {gettext("Executions")}
            </.button>
            <.button id="dashboard-flows-link" navigate={~p"/flows"} variant="primary">
              <.icon name="hero-squares-2x2" class="size-4" /> {gettext("Manage Flows")}
            </.button>
          </div>
          <.button
            :if={not @in_workspace? and @system_admin?}
            id="dashboard-create-workspace"
            navigate={~p"/workspaces"}
            variant="primary"
          >
            {gettext("Create a workspace")}
          </.button>
        </header>

        <%= if @in_workspace? do %>
          <div id="dashboard-stats" class="mb-6 grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
            <.stat
              id="stat-runs"
              label={gettext("Runs")}
              value={format_count(@overview.totals.runs)}
              icon="hero-play-circle"
              delta={change(@overview.totals.runs, @overview.previous.runs)}
              days={@days}
            />
            <.stat
              id="stat-success-rate"
              label={gettext("Success rate")}
              value={format_percent(@overview.totals.success_rate)}
              icon="hero-check-circle"
              delta={points(@overview.totals.success_rate, @overview.previous.success_rate)}
              good={:up}
              days={@days}
            >
              <.meter value={@overview.totals.success_rate} />
            </.stat>
            <.stat
              id="stat-failures"
              label={gettext("Failures")}
              value={format_count(@overview.totals.failed)}
              icon="hero-exclamation-triangle"
              delta={change(@overview.totals.failed, @overview.previous.failed)}
              good={:down}
              days={@days}
            />
            <.stat
              id="stat-duration"
              label={gettext("Average duration")}
              value={format_duration(@overview.totals.avg_duration)}
              icon="hero-clock"
              delta={change(@overview.totals.avg_duration, @overview.previous.avg_duration)}
              good={:down}
              days={@days}
            />
          </div>

          <div class="grid grid-cols-1 gap-6 lg:grid-cols-3">
            <div class="flex min-w-0 flex-col gap-6 lg:col-span-2">
              <.activity_chart days={@overview.days} />
              <.recent_runs runs={@overview.recent} now={@now} />
            </div>
            <div class="flex min-w-0 flex-col gap-6">
              <.attention flows={@overview.attention} now={@now} days={@days} />
              <.latest_flows
                flows={@overview.latest_flows}
                counts={@overview.flows}
                now={@now}
                can_edit={@can_edit?}
              />
            </div>
          </div>
        <% else %>
          <div
            id="dashboard-no-workspace"
            class={[card_classes(), "mx-auto max-w-md p-10 text-center"]}
          >
            <div class="mx-auto mb-4 flex size-12 items-center justify-center rounded-full bg-primary/10">
              <.icon name="hero-user-group" class="size-6 text-primary" />
            </div>
            <p class="text-sm text-gray-600 dark:text-gray-300">
              {gettext("Flows, runs and credentials live in a workspace.")}
            </p>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  attr :active, :map, required: true

  # What is going on now, shown only while something is.
  defp live_now(assigns) do
    ~H"""
    <.link
      :if={@active.running + @active.queued + @active.waiting > 0}
      id="dashboard-live"
      navigate={~p"/executions"}
      class="inline-flex min-h-9 flex-wrap items-center gap-x-3 gap-y-1 rounded-full border border-gray-200 bg-white px-3.5 py-1.5 text-xs font-medium text-gray-700 shadow-sm transition hover:border-gray-300 dark:border-slate-700 dark:bg-slate-900 dark:text-gray-200 dark:hover:border-slate-600"
    >
      <span :if={@active.running > 0} class="flex items-center gap-1.5 whitespace-nowrap">
        <HeddleUI.Components.ExecutionStatus.status_dot status="running" />
        {gettext("%{count} running", count: @active.running)}
      </span>
      <span :if={@active.queued > 0} class="flex items-center gap-1.5 whitespace-nowrap">
        <HeddleUI.Components.ExecutionStatus.status_dot status="queued" />
        {gettext("%{count} queued", count: @active.queued)}
      </span>
      <span :if={@active.waiting > 0} class="flex items-center gap-1.5 whitespace-nowrap">
        <HeddleUI.Components.ExecutionStatus.status_dot status="waiting" />
        {gettext("%{count} waiting", count: @active.waiting)}
      </span>
    </.link>
    """
  end

  # The change from the period before, in percent. Nil when there is nothing to compare.
  defp change(nil, _before), do: nil
  defp change(_now, nil), do: nil
  defp change(now, before) when before == 0 and now == 0, do: %{direction: :flat, text: "0%"}
  defp change(_now, before) when before == 0, do: nil

  defp change(now, before) do
    percent = round((now - before) * 100 / before)
    %{direction: direction(percent), text: "#{abs(percent)}%"}
  end

  # The change of a rate, in points.
  defp points(nil, _before), do: nil
  defp points(_now, nil), do: nil

  defp points(now, before) do
    diff = Float.round((now - before) * 1.0, 1)
    text = gettext("%{count} pts", count: format_number(abs(diff)))
    %{direction: direction(diff), text: text}
  end

  defp direction(value) when value > 0, do: :up
  defp direction(value) when value < 0, do: :down
  defp direction(_zero), do: :flat

  defp format_percent(nil), do: "—"
  defp format_percent(value), do: format_number(Float.round(value * 1.0, 1)) <> "%"

  defp format_number(value) when is_float(value) do
    if value == Float.round(value),
      do: Integer.to_string(trunc(value)),
      else: Float.to_string(value)
  end

  defp format_count(count) when count >= 10_000,
    do: "#{Float.round(count / 1000, 1)}K"

  defp format_count(count), do: Integer.to_string(count)
end
