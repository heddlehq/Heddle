defmodule HeddleUI.Components.Dashboard do
  @moduledoc """
  The parts of the dashboard: its figures, the chart of runs by day, the latest runs,
  the flows that fail and the flows changed last. They take what
  `HeddleCore.Executions.Overview` counted, and read nothing on their own.
  """
  use HeddleUI, :html

  import HeddleUI.Components.ExecutionStatus

  @card "rounded-2xl border border-gray-200 bg-white shadow-sm dark:border-slate-800 dark:bg-slate-900"

  @doc "The classes of a card of the dashboard."
  def card_classes, do: @card

  # ── Figures ─────────────────────────────────────────────────────────────────

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :icon, :string, required: true
  attr :delta, :any, default: nil, doc: "the change from the period before, or nil"
  attr :good, :atom, default: :neutral, values: [:up, :down, :neutral], doc: "which way is better"
  attr :days, :integer, required: true
  slot :inner_block

  def stat(assigns) do
    ~H"""
    <div
      id={@id}
      class={[card_classes(), "group relative flex flex-col p-5 transition hover:shadow-md"]}
    >
      <div class="flex items-center justify-between gap-3">
        <h3 class="text-sm font-medium text-gray-500 dark:text-gray-400">{@label}</h3>
        <span class="flex size-8 items-center justify-center rounded-lg bg-gray-50 text-gray-500 transition group-hover:bg-primary/10 group-hover:text-primary dark:bg-slate-800 dark:text-gray-400">
          <.icon name={@icon} class="size-4" />
        </span>
      </div>
      <p class="mt-3 text-3xl font-semibold tracking-tight text-gray-900 dark:text-white">
        {@value}
      </p>
      <div class="mt-auto pt-3">
        {render_slot(@inner_block)}
        <.delta :if={@delta} delta={@delta} good={@good} days={@days} />
        <p :if={is_nil(@delta)} class="text-xs text-gray-500 dark:text-gray-400">
          {gettext("No runs to compare with")}
        </p>
      </div>
    </div>
    """
  end

  attr :delta, :map, required: true
  attr :good, :atom, required: true
  attr :days, :integer, required: true

  defp delta(assigns) do
    assigns = assign(assigns, :tone, tone(assigns.delta, assigns.good))

    ~H"""
    <p class="flex flex-wrap items-center gap-x-1.5 gap-y-1 text-xs text-gray-500 dark:text-gray-400">
      <span class={[
        "inline-flex shrink-0 items-center gap-0.5 whitespace-nowrap rounded-md px-1.5 py-0.5 font-semibold",
        @tone == :good &&
          "bg-emerald-50 text-emerald-700 dark:bg-emerald-950/50 dark:text-emerald-300",
        @tone == :bad && "bg-red-50 text-red-700 dark:bg-red-950/50 dark:text-red-300",
        @tone == :neutral && "bg-gray-100 text-gray-600 dark:bg-slate-800 dark:text-gray-300"
      ]}>
        <.icon name={delta_icon(@delta.direction)} class="size-3" />
        {@delta.text}
      </span>
      {gettext("vs the %{count} days before", count: @days)}
    </p>
    """
  end

  defp tone(%{direction: :flat}, _good), do: :neutral
  defp tone(_delta, :neutral), do: :neutral
  defp tone(%{direction: direction}, good), do: if(direction == good, do: :good, else: :bad)

  defp delta_icon(:up), do: "hero-arrow-trending-up-micro"
  defp delta_icon(:down), do: "hero-arrow-trending-down-micro"
  defp delta_icon(:flat), do: "hero-minus-micro"

  attr :value, :any, required: true, doc: "a percentage, or nil"

  def meter(assigns) do
    ~H"""
    <div
      :if={@value}
      class="mb-2 h-1.5 w-full overflow-hidden rounded-full bg-gray-100 dark:bg-slate-800"
      role="meter"
      aria-valuemin="0"
      aria-valuemax="100"
      aria-valuenow={round(@value)}
    >
      <div
        class={[
          "h-full rounded-full transition-all duration-500",
          cond do
            @value >= 95 -> "bg-emerald-500"
            @value >= 80 -> "bg-amber-500"
            true -> "bg-red-500"
          end
        ]}
        style={"width: #{@value}%"}
      />
    </div>
    """
  end

  # ── Runs by day ─────────────────────────────────────────────────────────────

  attr :days, :list, required: true

  def activity_chart(assigns) do
    max = assigns.days |> Enum.map(&day_total/1) |> Enum.max(fn -> 0 end)
    top = nice_ceiling(max)

    assigns =
      assign(assigns,
        top: top,
        ticks: [top, div(top, 2), 0],
        empty?: max == 0,
        today: List.last(assigns.days).date
      )

    ~H"""
    <section id="dashboard-activity" class={[card_classes(), "p-5"]}>
      <div class="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h2 class="text-base font-semibold text-gray-900 dark:text-white">
            {gettext("Activity")}
          </h2>
          <p class="mt-0.5 text-sm text-gray-500 dark:text-gray-400">
            {gettext("Runs started each day, in the last %{count} days", count: length(@days))}
          </p>
        </div>
        <ul class="flex items-center gap-4 text-xs text-gray-600 dark:text-gray-300">
          <li class="flex items-center gap-1.5">
            <span class="size-2.5 rounded-sm bg-emerald-500"></span>{gettext("Succeeded")}
          </li>
          <li class="flex items-center gap-1.5">
            <span class="size-2.5 rounded-sm bg-red-500"></span>{gettext("Failed")}
          </li>
          <li class="flex items-center gap-1.5">
            <span class="size-2.5 rounded-sm bg-gray-300 dark:bg-slate-600"></span>{gettext(
              "In progress"
            )}
          </li>
        </ul>
      </div>

      <div class="relative mt-6 flex gap-3">
        <div
          class="flex h-48 w-7 shrink-0 flex-col justify-between text-right text-[11px] tabular-nums text-gray-400 dark:text-gray-500"
          aria-hidden="true"
        >
          <span :for={tick <- @ticks} class="-translate-y-1/2 leading-none last:translate-y-1/2">
            {tick}
          </span>
        </div>

        <div class="relative min-w-0 flex-1">
          <div class="pointer-events-none absolute inset-x-0 top-0 h-48" aria-hidden="true">
            <div class="absolute inset-x-0 top-0 border-t border-gray-100 dark:border-slate-800">
            </div>
            <div class="absolute inset-x-0 top-1/2 border-t border-gray-100 dark:border-slate-800">
            </div>
            <div class="absolute inset-x-0 bottom-0 border-t border-gray-200 dark:border-slate-700">
            </div>
          </div>

          <div
            :if={@empty?}
            id="dashboard-activity-empty"
            class="absolute inset-x-0 top-0 flex h-48 items-center justify-center"
          >
            <p class="rounded-lg bg-white/80 px-3 py-1.5 text-sm text-gray-500 backdrop-blur dark:bg-slate-900/80 dark:text-gray-400">
              {gettext("No runs in this period yet")}
            </p>
          </div>

          <ol class="relative flex h-48 items-end" aria-hidden="true">
            <li
              :for={day <- @days}
              class="group relative flex h-full flex-1 cursor-default items-end justify-center outline-none"
              tabindex="0"
            >
              <div
                :if={day_total(day) > 0}
                class="flex w-full max-w-6 flex-col-reverse gap-[2px] overflow-hidden rounded-t-[4px] transition-opacity group-hover:opacity-80 sm:mx-1"
                style={"height: #{day_total(day) * 100 / @top}%"}
              >
                <div
                  :if={day.succeeded > 0}
                  class="w-full bg-emerald-500"
                  style={"flex: #{day.succeeded} 1 0"}
                />
                <div :if={day.failed > 0} class="w-full bg-red-500" style={"flex: #{day.failed} 1 0"} />
                <div
                  :if={day.other > 0}
                  class="w-full bg-gray-300 dark:bg-slate-600"
                  style={"flex: #{day.other} 1 0"}
                />
              </div>
              <div class="pointer-events-none absolute bottom-full left-1/2 z-10 mb-2 hidden w-max -translate-x-1/2 rounded-lg border border-gray-200 bg-white px-3 py-2 text-xs shadow-lg group-hover:block group-focus:block dark:border-slate-700 dark:bg-slate-800">
                <p class="font-semibold text-gray-900 dark:text-white">{format_day(day.date)}</p>
                <dl class="mt-1 grid grid-cols-[auto_auto] gap-x-4 gap-y-0.5 tabular-nums">
                  <dt class="flex items-center gap-1.5 text-gray-500 dark:text-gray-400">
                    <span class="size-2 rounded-sm bg-emerald-500"></span>{gettext("Succeeded")}
                  </dt>
                  <dd class="text-right text-gray-900 dark:text-white">{day.succeeded}</dd>
                  <dt class="flex items-center gap-1.5 text-gray-500 dark:text-gray-400">
                    <span class="size-2 rounded-sm bg-red-500"></span>{gettext("Failed")}
                  </dt>
                  <dd class="text-right text-gray-900 dark:text-white">{day.failed}</dd>
                  <dt class="flex items-center gap-1.5 text-gray-500 dark:text-gray-400">
                    <span class="size-2 rounded-sm bg-gray-300 dark:bg-slate-600"></span>{gettext(
                      "In progress"
                    )}
                  </dt>
                  <dd class="text-right text-gray-900 dark:text-white">{day.other}</dd>
                </dl>
              </div>
            </li>
          </ol>

          <ol
            class="mt-2 flex text-[11px] tabular-nums text-gray-400 dark:text-gray-500"
            aria-hidden="true"
          >
            <li
              :for={{day, index} <- Enum.with_index(@days)}
              class={[
                "flex-1 text-center",
                rem(length(@days) - 1 - index, 2) == 1 && "max-sm:invisible",
                day.date == @today && "font-semibold text-gray-600 dark:text-gray-300"
              ]}
            >
              {Calendar.strftime(day.date, "%d")}
            </li>
          </ol>
        </div>
      </div>

      <table class="sr-only">
        <caption>{gettext("Runs started each day")}</caption>
        <thead>
          <tr>
            <th scope="col">{gettext("Day")}</th>
            <th scope="col">{gettext("Succeeded")}</th>
            <th scope="col">{gettext("Failed")}</th>
            <th scope="col">{gettext("In progress")}</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={day <- @days}>
            <th scope="row">{format_day(day.date)}</th>
            <td>{day.succeeded}</td>
            <td>{day.failed}</td>
            <td>{day.other}</td>
          </tr>
        </tbody>
      </table>
    </section>
    """
  end

  defp day_total(day), do: day.succeeded + day.failed + day.other

  # A round top for the axis, divisible by 2 so its middle is whole: 4, 10, 20, 50…
  defp nice_ceiling(max) when max <= 4, do: 4

  defp nice_ceiling(max) do
    magnitude = Integer.pow(10, trunc(:math.log10(max)))
    Enum.find([2, 4, 6, 10], &(&1 * magnitude >= max)) * magnitude
  end

  defp format_day(date) do
    Calendar.strftime(date, "%Y-%m-%d")
  end

  # ── Latest runs ─────────────────────────────────────────────────────────────

  attr :runs, :list, required: true
  attr :now, :any, required: true

  def recent_runs(assigns) do
    ~H"""
    <section id="dashboard-recent-runs" class={[card_classes(), "overflow-hidden"]}>
      <.card_header
        title={gettext("Recent runs")}
        link={~p"/executions"}
        link_label={gettext("All runs")}
      />

      <%= if @runs == [] do %>
        <div id="dashboard-recent-runs-empty" class="px-5 pb-8 pt-4 text-center">
          <div class="mx-auto mb-3 flex size-10 items-center justify-center rounded-full bg-gray-100 dark:bg-slate-800">
            <.icon name="hero-play" class="size-5 text-gray-400" />
          </div>
          <p class="text-sm text-gray-500 dark:text-gray-400">
            {gettext("Runs show here as soon as a flow runs.")}
          </p>
        </div>
      <% else %>
        <ul role="list" class="divide-y divide-gray-100 dark:divide-slate-800">
          <li :for={run <- @runs}>
            <.link
              id={"dashboard-run-#{run.public_id}"}
              navigate={~p"/executions/#{run.public_id}"}
              class="group flex items-center gap-4 px-5 py-3 transition hover:bg-gray-50 dark:hover:bg-slate-800/60"
            >
              <.status_badge status={run.status} class="w-24 shrink-0 justify-center" />
              <div class="min-w-0 flex-1">
                <p class="truncate text-sm font-medium text-gray-900 dark:text-white">
                  {(run.flow && run.flow.name) || gettext("Deleted flow")}
                </p>
                <p class="mt-0.5 truncate font-mono text-[11px] text-gray-500 dark:text-gray-400">
                  {run.public_id}
                </p>
              </div>
              <span class="hidden shrink-0 items-center gap-1 rounded-md bg-gray-100 px-2 py-0.5 text-xs text-gray-600 sm:inline-flex dark:bg-slate-800 dark:text-gray-300">
                <.icon name={trigger_icon(trigger(run))} class="size-3.5" />
                {trigger_label(trigger(run))}
              </span>
              <div class="w-20 shrink-0 text-right">
                <p
                  class="text-xs text-gray-700 dark:text-gray-200"
                  title={format_datetime(run.inserted_at)}
                >
                  {ago(run.inserted_at, @now)}
                </p>
                <p class="mt-0.5 text-[11px] tabular-nums text-gray-500 dark:text-gray-400">
                  {run_duration(run)}
                </p>
              </div>
              <.icon
                name="hero-chevron-right-mini"
                class="size-4 shrink-0 text-gray-300 transition group-hover:translate-x-0.5 group-hover:text-gray-500 dark:text-slate-600 dark:group-hover:text-gray-400"
              />
            </.link>
          </li>
        </ul>
      <% end %>
    </section>
    """
  end

  defp trigger(%{input: %{"section_id" => _id}}), do: "section"

  defp trigger(%{input: input}) when is_map(input),
    do: input["trigger"] || input["source"] || "manual"

  defp trigger(_run), do: "manual"

  defp trigger_label("manual"), do: gettext("Manual")
  defp trigger_label("webhook"), do: gettext("Webhook")
  defp trigger_label("schedule"), do: gettext("Schedule")
  defp trigger_label("form"), do: gettext("Form")
  defp trigger_label("error"), do: gettext("Error flow")
  defp trigger_label("subflow"), do: gettext("Subflow")
  defp trigger_label("section"), do: gettext("Section")
  defp trigger_label(other), do: other

  defp trigger_icon("webhook"), do: "hero-globe-alt-micro"
  defp trigger_icon("schedule"), do: "hero-clock-micro"
  defp trigger_icon("form"), do: "hero-document-text-micro"
  defp trigger_icon("error"), do: "hero-exclamation-triangle-micro"
  defp trigger_icon("subflow"), do: "hero-arrow-turn-down-right-micro"
  defp trigger_icon("section"), do: "hero-rectangle-group-micro"
  defp trigger_icon(_manual), do: "hero-cursor-arrow-rays-micro"

  defp run_duration(%{started_at: %DateTime{} = started, finished_at: %DateTime{} = finished}),
    do: format_duration(DateTime.diff(finished, started))

  defp run_duration(%{status: status}) when status in ~w(queued running waiting), do: "…"
  defp run_duration(_run), do: "—"

  # ── Flows that fail ─────────────────────────────────────────────────────────

  attr :flows, :list, required: true
  attr :now, :any, required: true
  attr :days, :integer, required: true

  def attention(assigns) do
    ~H"""
    <section id="dashboard-attention" class={[card_classes(), "overflow-hidden"]}>
      <.card_header title={gettext("Needs attention")} />

      <%= if @flows == [] do %>
        <div id="dashboard-attention-empty" class="flex items-center gap-3 px-5 pb-5 pt-1">
          <span class="flex size-9 shrink-0 items-center justify-center rounded-full bg-emerald-50 text-emerald-600 dark:bg-emerald-950/50 dark:text-emerald-400">
            <.icon name="hero-check-badge" class="size-5" />
          </span>
          <p class="text-sm text-gray-600 dark:text-gray-300">
            {gettext("No flow failed in the last %{count} days.", count: @days)}
          </p>
        </div>
      <% else %>
        <ul role="list" class="divide-y divide-gray-100 dark:divide-slate-800">
          <li :for={flow <- @flows}>
            <.link
              id={"dashboard-attention-#{flow.id}"}
              navigate={~p"/flows/#{flow.id}"}
              class="block px-5 py-3 transition hover:bg-gray-50 dark:hover:bg-slate-800/60"
            >
              <div class="flex items-center justify-between gap-3">
                <p class="truncate text-sm font-medium text-gray-900 dark:text-white">{flow.name}</p>
                <span class="shrink-0 text-xs font-semibold tabular-nums text-red-700 dark:text-red-300">
                  {ngettext("1 failure", "%{count} failures", flow.failed)}
                </span>
              </div>
              <div class="mt-2 flex h-1 w-full gap-[2px] overflow-hidden rounded-full">
                <div class="h-full rounded-full bg-red-500" style={"flex: #{flow.failed} 1 0"} />
                <div
                  :if={flow.runs > flow.failed}
                  class="h-full rounded-full bg-gray-200 dark:bg-slate-700"
                  style={"flex: #{flow.runs - flow.failed} 1 0"}
                />
              </div>
              <p class="mt-1.5 text-xs text-gray-500 dark:text-gray-400">
                {gettext("%{failed} of %{runs} runs · last %{ago}",
                  failed: flow.failed,
                  runs: flow.runs,
                  ago: ago(flow.last_failed_at, @now)
                )}
              </p>
            </.link>
          </li>
        </ul>
      <% end %>
    </section>
    """
  end

  # ── Flows changed last ──────────────────────────────────────────────────────

  attr :flows, :list, required: true
  attr :counts, :map, required: true
  attr :now, :any, required: true
  attr :can_edit, :boolean, required: true

  def latest_flows(assigns) do
    ~H"""
    <section id="dashboard-flows" class={[card_classes(), "overflow-hidden"]}>
      <.card_header title={gettext("Flows")} link={~p"/flows"} link_label={gettext("All flows")} />

      <%= if @flows == [] do %>
        <div id="dashboard-flows-empty" class="px-5 pb-6 pt-2 text-center">
          <div class="mx-auto mb-3 flex size-10 items-center justify-center rounded-full bg-primary/10">
            <.icon name="hero-squares-plus" class="size-5 text-primary" />
          </div>
          <p class="text-sm font-medium text-gray-900 dark:text-white">{gettext("No flows")}</p>
          <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
            {gettext("Get started by creating a new workflow automation.")}
          </p>
          <.button :if={@can_edit} navigate={~p"/flows"} variant="outline" class="mt-4">
            {gettext("Create Flow")} <.icon name="hero-arrow-right-mini" class="size-4" />
          </.button>
        </div>
      <% else %>
        <div class="px-5 pb-3">
          <div class="flex items-baseline justify-between text-xs text-gray-500 dark:text-gray-400">
            <span>
              {gettext("%{published} of %{total} published",
                published: @counts.published,
                total: @counts.total
              )}
            </span>
          </div>
          <div class="mt-1.5 flex h-1 w-full gap-[2px] overflow-hidden rounded-full">
            <div
              :if={@counts.published > 0}
              class="h-full rounded-full bg-primary"
              style={"flex: #{@counts.published} 1 0"}
            />
            <div
              :if={@counts.total > @counts.published}
              class="h-full rounded-full bg-gray-200 dark:bg-slate-700"
              style={"flex: #{@counts.total - @counts.published} 1 0"}
            />
          </div>
        </div>
        <ul
          role="list"
          class="divide-y divide-gray-100 border-t border-gray-100 dark:divide-slate-800 dark:border-slate-800"
        >
          <li :for={flow <- @flows}>
            <.link
              id={"dashboard-flow-#{flow.id}"}
              navigate={~p"/flows/#{flow.id}"}
              class="group flex items-center gap-3 px-5 py-3 transition hover:bg-gray-50 dark:hover:bg-slate-800/60"
            >
              <span class="flex size-8 shrink-0 items-center justify-center rounded-lg bg-primary/10 text-primary">
                <.icon name="hero-bolt-mini" class="size-4" />
              </span>
              <div class="min-w-0 flex-1">
                <p class="truncate text-sm font-medium text-gray-900 dark:text-white">{flow.name}</p>
                <p class="mt-0.5 flex items-center gap-1.5 text-xs text-gray-500 dark:text-gray-400">
                  <%= if flow.last_run do %>
                    <.status_dot status={flow.last_run.status} />
                    {gettext("ran %{ago}", ago: ago(flow.last_run.inserted_at, @now))}
                  <% else %>
                    {gettext("never ran")}
                  <% end %>
                </p>
              </div>
              <span class={[
                "shrink-0 rounded-md px-1.5 py-0.5 text-[11px] font-medium",
                if(flow.published?,
                  do: "bg-primary/10 text-primary",
                  else: "bg-gray-100 text-gray-600 dark:bg-slate-800 dark:text-gray-300"
                )
              ]}>
                {if flow.published?,
                  do: pgettext("flow", "Published"),
                  else: pgettext("flow", "Draft")}
              </span>
            </.link>
          </li>
        </ul>
      <% end %>
    </section>
    """
  end

  attr :title, :string, required: true
  attr :link, :string, default: nil
  attr :link_label, :string, default: nil

  defp card_header(assigns) do
    ~H"""
    <div class="flex items-center justify-between gap-3 px-5 pb-3 pt-4">
      <h2 class="text-base font-semibold text-gray-900 dark:text-white">{@title}</h2>
      <.link
        :if={@link}
        navigate={@link}
        class="group inline-flex items-center gap-0.5 text-xs font-medium text-primary hover:underline"
      >
        {@link_label}
        <.icon name="hero-arrow-right-micro" class="size-3.5 transition group-hover:translate-x-0.5" />
      </.link>
    </div>
    """
  end

  # ── Formatting ──────────────────────────────────────────────────────────────

  @doc "How long ago `datetime` was, from `now`, in words."
  def ago(nil, _now), do: "—"

  def ago(%NaiveDateTime{} = datetime, now),
    do: ago(DateTime.from_naive!(datetime, "Etc/UTC"), now)

  def ago(datetime, now) do
    seconds = max(DateTime.diff(now, datetime), 0)

    cond do
      seconds < 60 -> gettext("just now")
      seconds < 3600 -> gettext("%{count} min ago", count: div(seconds, 60))
      seconds < 86_400 -> gettext("%{count} h ago", count: div(seconds, 3600))
      seconds < 30 * 86_400 -> ngettext("1 day ago", "%{count} days ago", div(seconds, 86_400))
      true -> Calendar.strftime(datetime, "%d/%m/%Y")
    end
  end

  @doc "A duration in seconds, short: 0.4 s, 12 s, 3 min 5 s, 2 h 10 min."
  def format_duration(nil), do: "—"

  def format_duration(seconds) when is_float(seconds) and seconds < 10,
    do: gettext("%{count} s", count: :erlang.float_to_binary(seconds, decimals: 1))

  def format_duration(seconds) do
    seconds = round(seconds)

    cond do
      seconds < 60 ->
        gettext("%{count} s", count: seconds)

      seconds < 3600 ->
        gettext("%{min} min %{s} s", min: div(seconds, 60), s: rem(seconds, 60))

      true ->
        gettext("%{h} h %{min} min", h: div(seconds, 3600), min: div(rem(seconds, 3600), 60))
    end
  end

  defp format_datetime(%DateTime{} = datetime),
    do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S UTC")
end
