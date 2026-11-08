defmodule HeddleUI.Components.Flow.RunInspector do
  @moduledoc """
  The panel under the canvas that shows a run step by step: a timeline of the steps,
  with how long each took, and for the one picked, the context it got, what it changed
  and why it failed.

  Its state comes from `HeddleUI.FlowLive.InspectorManager`. The values are drawn by
  the `json-tree` element (`assets/js/json-tree.js`).
  """

  use HeddleUI, :html

  alias HeddleUI.FlowLive.InspectorManager

  attr :inspector, :map, default: nil

  def run_inspector(assigns) do
    ~H"""
    <section
      :if={@inspector}
      id="run-inspector"
      class={[
        "relative z-20 flex shrink-0 flex-col border-t border-gray-200 bg-white shadow-[0_-8px_24px_-12px_rgba(0,0,0,0.18)] transition-[height] duration-300 ease-[cubic-bezier(0.16,1,0.3,1)] dark:border-slate-700 dark:bg-slate-900 dark:shadow-black/50",
        if(@inspector.collapsed, do: "h-12", else: "h-[min(26rem,48vh)]")
      ]}
    >
      <.inspector_header inspector={@inspector} />
      <div :if={!@inspector.collapsed} class="flex min-h-0 flex-1">
        <.timeline inspector={@inspector} />
        <.step_detail inspector={@inspector} />
      </div>
    </section>
    """
  end

  attr :inspector, :map, required: true

  defp inspector_header(assigns) do
    assigns =
      assigns
      |> assign(:execution, assigns.inspector.execution)
      |> assign(:total_ms, InspectorManager.total_ms(assigns.inspector))

    ~H"""
    <header class="flex h-12 shrink-0 items-center gap-3 border-b border-gray-200 px-4 dark:border-slate-800">
      <button
        id="run-inspector-toggle"
        type="button"
        phx-click="inspector_toggle"
        class="flex min-w-0 items-center gap-3 rounded-md py-1 pr-2 text-left transition hover:opacity-80"
        aria-label={gettext("Show or hide the inspector")}
      >
        <.icon
          name="hero-chevron-down"
          class={[
            "size-4 shrink-0 text-gray-500 transition-transform duration-200 dark:text-gray-400",
            @inspector.collapsed && "-rotate-180"
          ]}
        />
        <span class="text-sm font-semibold text-gray-900 dark:text-white">
          {gettext("Run inspector")}
        </span>
      </button>
      <.status_pill id="run-inspector-status" status={@execution.status} />
      <span class="hidden truncate font-mono text-xs text-gray-500 md:inline dark:text-gray-400">
        {@execution.public_id}
      </span>
      <span
        :if={@total_ms}
        id="run-inspector-total"
        class="hidden items-center gap-1 text-xs text-gray-500 sm:inline-flex dark:text-gray-400"
      >
        <.icon name="hero-clock" class="size-3.5" /> {format_ms(@total_ms)}
      </span>
      <span class="hidden text-xs text-gray-500 sm:inline dark:text-gray-400">
        {ngettext("1 step", "%{count} steps", length(@inspector.steps))}
      </span>

      <div class="ml-auto flex items-center gap-1">
        <button
          :if={@execution.status not in ["queued", "running"]}
          id="run-inspector-rerun"
          type="button"
          phx-click="inspector_rerun"
          class="inline-flex h-8 items-center gap-1.5 rounded-md px-2.5 text-xs font-semibold text-gray-700 transition hover:bg-gray-100 hover:text-primary dark:text-gray-200 dark:hover:bg-slate-800"
          title={gettext("Save the flow and run it again with the same input")}
        >
          <.icon name="hero-arrow-path" class="size-4" />
          <span class="hidden sm:inline">{gettext("Run again")}</span>
        </button>
        <.link
          navigate={~p"/executions/#{@execution.public_id}"}
          class="inline-flex h-8 items-center gap-1.5 rounded-md px-2.5 text-xs font-semibold text-gray-700 transition hover:bg-gray-100 hover:text-primary dark:text-gray-200 dark:hover:bg-slate-800"
        >
          <.icon name="hero-arrow-top-right-on-square" class="size-4" />
          <span class="hidden lg:inline">{gettext("Executions")}</span>
        </.link>
        <button
          id="run-inspector-close"
          type="button"
          phx-click="inspector_close"
          class="rounded-md p-1.5 text-gray-500 transition hover:bg-gray-100 hover:text-gray-900 dark:text-gray-400 dark:hover:bg-slate-800 dark:hover:text-white"
          aria-label={gettext("Close the inspector")}
        >
          <.icon name="hero-x-mark" class="size-4" />
        </button>
      </div>
    </header>
    """
  end

  attr :inspector, :map, required: true

  defp timeline(assigns) do
    assigns =
      assigns
      |> assign(:rows, InspectorManager.rows(assigns.inspector))
      |> assign(:hidden, InspectorManager.hidden_rows(assigns.inspector))

    ~H"""
    <nav
      id="run-timeline"
      class="flex w-[min(24rem,42%)] shrink-0 flex-col overflow-y-auto border-r border-gray-200 py-1 dark:border-slate-800"
      aria-label={gettext("Steps of the run")}
    >
      <p
        :if={@rows == [] and @inspector.execution.status in ["queued", "running"]}
        id="run-timeline-waiting"
        class="flex items-center gap-2 px-4 py-6 text-sm text-gray-500 dark:text-gray-400"
      >
        <.icon name="hero-arrow-path" class="size-4 animate-spin" />
        {gettext("Waiting for the first step...")}
      </p>
      <p
        :if={@rows == [] and @inspector.execution.status not in ["queued", "running"]}
        class="px-4 py-6 text-sm text-gray-500 dark:text-gray-400"
      >
        {gettext("This run kept no steps.")}
      </p>

      <button
        :for={row <- @rows}
        id={"run-step-#{row.index}"}
        type="button"
        phx-click="inspector_select"
        phx-value-index={row.index}
        class={[
          "group relative flex w-full items-center gap-2.5 px-3 py-1.5 text-left transition",
          if(@inspector.selected == row.index,
            do: "bg-primary/10",
            else: "hover:bg-gray-50 dark:hover:bg-slate-800/60"
          )
        ]}
      >
        <span
          :if={@inspector.selected == row.index}
          class="absolute inset-y-1 left-0 w-0.5 rounded-full bg-primary"
        />
        <.status_dot status={row.step["status"]} continued={row.step["continued"] == true} />
        <span class="w-28 min-w-0 shrink-0">
          <span class="block truncate text-[13px] font-medium text-gray-900 dark:text-gray-100">
            {step_name(row.step)}
          </span>
          <span
            :if={row.step["label"]}
            class="block truncate text-[11px] text-gray-500 dark:text-gray-400"
          >
            {row.step["node_type"]}
          </span>
        </span>
        <span class="relative h-1.5 min-w-0 flex-1 overflow-hidden rounded-full bg-gray-100 dark:bg-slate-800">
          <span
            class={[
              "absolute inset-y-0 rounded-full",
              bar_class(row.step["status"], row.step["continued"] == true)
            ]}
            style={"left: #{row.offset}%; width: #{row.width}%"}
          />
        </span>
        <span class="flex w-[4.5rem] shrink-0 items-center justify-end gap-1">
          <.icon
            :if={row.step["pinned"]}
            name="hero-bookmark-solid"
            class="size-3 text-primary"
          />
          <span
            :if={row.step["attempts"]}
            class="rounded bg-amber-500/15 px-1 text-[10px] font-semibold text-amber-700 dark:text-amber-300"
            title={gettext("Tries")}
          >
            ×{row.step["attempts"]}
          </span>
          <span class="font-mono text-[11px] tabular-nums text-gray-500 dark:text-gray-400">
            {format_ms(row.step["duration_ms"])}
          </span>
        </span>
      </button>

      <p :if={@hidden > 0} class="px-4 py-2 text-xs text-gray-500 dark:text-gray-400">
        {ngettext("1 more step isn't shown.", "%{count} more steps aren't shown.", @hidden)}
      </p>

      <button
        :if={@inspector.execution.status in ["succeeded", "failed", "waiting"]}
        id="run-step-result"
        type="button"
        phx-click="inspector_select"
        phx-value-index="result"
        class={[
          "mt-1 flex w-full items-center gap-2.5 border-t border-gray-100 px-3 py-2 text-left transition dark:border-slate-800",
          if(@inspector.selected == :result,
            do: "bg-primary/10",
            else: "hover:bg-gray-50 dark:hover:bg-slate-800/60"
          )
        ]}
      >
        <.icon name="hero-flag" class="size-4 text-gray-500 dark:text-gray-400" />
        <span class="text-[13px] font-medium text-gray-900 dark:text-gray-100">
          {result_label(@inspector.execution.status)}
        </span>
      </button>
    </nav>
    """
  end

  attr :inspector, :map, required: true

  defp step_detail(%{inspector: %{selected: :result}} = assigns) do
    ~H"""
    <div id="run-step-detail" class="flex min-w-0 flex-1 flex-col">
      <div class="flex shrink-0 items-center gap-2 border-b border-gray-200 px-4 py-2.5 dark:border-slate-800">
        <.icon name="hero-flag" class="size-4 text-gray-500 dark:text-gray-400" />
        <h3 class="text-sm font-semibold text-gray-900 dark:text-white">
          {result_label(@inspector.execution.status)}
        </h3>
      </div>
      <div
        :if={@inspector.execution.error}
        class="shrink-0 border-b border-error/20 bg-error/5 px-4 py-3"
      >
        <pre class="whitespace-pre-wrap break-words font-mono text-xs leading-5 text-error">{@inspector.execution.error["message"]}</pre>
      </div>
      <.value_view
        id="run-result-json"
        value={@inspector.execution.result || %{}}
        empty={gettext("The run ended without a context.")}
      />
    </div>
    """
  end

  defp step_detail(assigns) do
    assigns = assign(assigns, :step, InspectorManager.selected_step(assigns.inspector))

    ~H"""
    <div id="run-step-detail" class="flex min-w-0 flex-1 flex-col">
      <%= if @step do %>
        <.step_heading step={@step} index={@inspector.selected} />
        <.step_tabs step={@step} tab={@inspector.tab} />
        <%= case @inspector.tab do %>
          <% "error" -> %>
            <div id="run-step-error" class="min-h-0 flex-1 overflow-auto px-4 py-3">
              <pre class="whitespace-pre-wrap break-words rounded-lg border border-error/20 bg-error/5 p-3 font-mono text-xs leading-5 text-error">{@step["error"]}</pre>
              <div :if={@step["retry_errors"]} class="mt-4 space-y-2">
                <p class="text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400">
                  {gettext("Earlier tries")}
                </p>
                <div
                  :for={{message, try} <- Enum.with_index(@step["retry_errors"], 1)}
                  class="rounded-md border border-gray-200 px-3 py-2 dark:border-slate-700"
                >
                  <p class="text-[11px] font-semibold text-gray-500 dark:text-gray-400">
                    {gettext("Try %{number}", number: try)}
                  </p>
                  <pre class="mt-1 whitespace-pre-wrap break-words font-mono text-xs text-gray-700 dark:text-gray-300">{message}</pre>
                </div>
              </div>
            </div>
          <% tab -> %>
            <.data_view step={@step} tab={tab} index={@inspector.selected} />
        <% end %>
      <% else %>
        <div class="flex flex-1 flex-col items-center justify-center gap-2 px-6 text-center">
          <.icon name="hero-cursor-arrow-rays" class="size-6 text-gray-400 dark:text-gray-500" />
          <p class="text-sm text-gray-500 dark:text-gray-400">
            {gettext("Pick a step to see what it got and what it did.")}
          </p>
        </div>
      <% end %>
    </div>
    """
  end

  attr :step, :map, required: true
  attr :index, :integer, required: true

  defp step_heading(assigns) do
    assigns = assign(assigns, :whole?, whole?(assigns.step))

    ~H"""
    <div class="flex shrink-0 flex-wrap items-center gap-x-3 gap-y-2 border-b border-gray-200 px-4 py-2.5 dark:border-slate-800">
      <div class="flex min-w-0 items-center gap-2">
        <.status_dot status={@step["status"]} continued={@step["continued"] == true} />
        <h3 id="run-step-name" class="truncate text-sm font-semibold text-gray-900 dark:text-white">
          {step_name(@step)}
        </h3>
        <span :if={@step["label"]} class="truncate text-xs text-gray-500 dark:text-gray-400">
          {@step["node_type"]}
        </span>
      </div>
      <div class="flex flex-wrap items-center gap-1.5">
        <.chip>
          <.icon name="hero-arrow-right" class="size-3" /> {@step["output"]}
        </.chip>
        <.chip>
          <.icon name="hero-clock" class="size-3" /> {format_ms(@step["duration_ms"])}
        </.chip>
        <.chip :if={@step["attempts"]} tone="warning">
          {gettext("%{count} tries", count: @step["attempts"])}
        </.chip>
        <.chip :if={@step["continued"]} tone="warning">{gettext("Failed, and went on")}</.chip>
        <.chip :if={@step["pinned"]} tone="primary">
          <.icon name="hero-bookmark-solid" class="size-3" /> {gettext("Pinned data")}
        </.chip>
      </div>
      <div class="ml-auto flex items-center gap-1">
        <button
          id="run-step-focus"
          type="button"
          phx-click="inspector_focus"
          class="rounded-md p-1.5 text-gray-500 transition hover:bg-gray-100 hover:text-primary dark:text-gray-400 dark:hover:bg-slate-800"
          title={gettext("Show on the canvas")}
        >
          <.icon name="hero-viewfinder-circle" class="size-4" />
        </button>
        <button
          :if={@step["pinned"]}
          id="run-step-unpin"
          type="button"
          phx-click="inspector_unpin"
          phx-value-node={@step["node_id"]}
          class="inline-flex h-7 items-center gap-1 rounded-md px-2 text-xs font-semibold text-gray-700 transition hover:bg-gray-100 hover:text-primary dark:text-gray-200 dark:hover:bg-slate-800"
        >
          <.icon name="hero-bookmark-slash" class="size-3.5" /> {gettext("Unpin")}
        </button>
        <button
          :if={!@step["pinned"] and @step["status"] == "success"}
          id="run-step-pin"
          type="button"
          phx-click="inspector_pin"
          phx-value-index={@index}
          disabled={!@whole?}
          class="inline-flex h-7 items-center gap-1 rounded-md px-2 text-xs font-semibold text-gray-700 transition hover:bg-gray-100 hover:text-primary disabled:cursor-not-allowed disabled:opacity-40 dark:text-gray-200 dark:hover:bg-slate-800"
          title={
            if(@whole?,
              do: gettext("Runs from the editor take this output instead of running the node"),
              else: gettext("Only part of this output was kept, so it can't be pinned")
            )
          }
        >
          <.icon name="hero-bookmark" class="size-3.5" /> {gettext("Pin output")}
        </button>
        <button
          id="run-step-replay"
          type="button"
          phx-click="inspector_replay"
          phx-value-index={@index}
          disabled={!@whole?}
          class="inline-flex h-7 items-center gap-1 rounded-md bg-primary px-2.5 text-xs font-semibold text-primary-content shadow-sm transition hover:opacity-90 active:scale-[0.98] disabled:cursor-not-allowed disabled:opacity-40"
          title={
            if(@whole?,
              do: gettext("Save the flow and run it from this step, with the context it got"),
              else:
                gettext("Only part of what this step got was kept, so it can't run again from here")
            )
          }
        >
          <.icon name="hero-play" class="size-3.5" /> {gettext("Run from here")}
        </button>
      </div>
    </div>
    """
  end

  attr :step, :map, required: true
  attr :tab, :string, required: true

  defp step_tabs(assigns) do
    ~H"""
    <div
      class="flex shrink-0 items-center gap-1 border-b border-gray-200 px-3 dark:border-slate-800"
      role="tablist"
    >
      <.tab id="run-tab-output" tab="output" current={@tab} label={gettext("Output")} />
      <.tab id="run-tab-input" tab="input" current={@tab} label={gettext("Input")} />
      <.tab
        :if={@step["error"]}
        id="run-tab-error"
        tab="error"
        current={@tab}
        label={gettext("Error")}
        tone="error"
      />
    </div>
    """
  end

  attr :id, :string, required: true
  attr :tab, :string, required: true
  attr :current, :string, required: true
  attr :label, :string, required: true
  attr :tone, :string, default: nil

  defp tab(assigns) do
    ~H"""
    <button
      id={@id}
      type="button"
      role="tab"
      aria-selected={to_string(@tab == @current)}
      phx-click="inspector_tab"
      phx-value-tab={@tab}
      class={[
        "relative px-2.5 py-2 text-xs font-semibold transition",
        cond do
          @tab == @current and @tone == "error" -> "text-error"
          @tab == @current -> "text-primary"
          true -> "text-gray-500 hover:text-gray-900 dark:text-gray-400 dark:hover:text-white"
        end
      ]}
    >
      {@label}
      <span
        :if={@tab == @current}
        class={[
          "absolute inset-x-2 -bottom-px h-0.5 rounded-full",
          if(@tone == "error", do: "bg-error", else: "bg-primary")
        ]}
      />
    </button>
    """
  end

  attr :step, :map, required: true
  attr :tab, :string, required: true
  attr :index, :integer, required: true

  defp data_view(assigns) do
    data = assigns.step["data"] || %{}

    assigns =
      assigns
      |> assign(:data, data)
      |> assign(:value, data[assigns.tab])

    ~H"""
    <%= cond do %>
      <% @data["omitted"] == true or @data == %{} -> %>
        <p id="run-step-omitted" class="px-4 py-6 text-sm text-gray-500 dark:text-gray-400">
          {gettext("This run took too many steps to keep the data of this one.")}
        </p>
      <% true -> %>
        <p
          :if={@data["truncated"]}
          class="flex shrink-0 items-center gap-1.5 border-b border-amber-500/20 bg-amber-500/10 px-4 py-1.5 text-xs text-amber-800 dark:text-amber-200"
        >
          <.icon name="hero-scissors" class="size-3.5" />
          {gettext("Long values were cut to keep the run small.")}
        </p>
        <p
          :if={@tab == "output" and @data["removed"]}
          class="shrink-0 border-b border-gray-200 px-4 py-1.5 text-xs text-gray-500 dark:border-slate-800 dark:text-gray-400"
        >
          {gettext("Removed: %{keys}", keys: Enum.join(@data["removed"], ", "))}
        </p>
        <.value_view
          id={"run-json-#{@index}-#{@tab}"}
          value={@value || %{}}
          empty={
            if(@tab == "output",
              do: gettext("This step changed nothing in the context."),
              else: gettext("This step got an empty context.")
            )
          }
        />
    <% end %>
    """
  end

  attr :id, :string, required: true
  attr :value, :any, required: true
  attr :empty, :string, required: true

  defp value_view(assigns) do
    ~H"""
    <%= if @value in [%{}, []] do %>
      <p class="px-4 py-6 text-sm text-gray-500 dark:text-gray-400">{@empty}</p>
    <% else %>
      <json-tree
        id={@id}
        phx-update="ignore"
        class="block min-h-0 flex-1 overflow-auto"
        data-value={Jason.encode!(@value)}
        data-labels={
          Jason.encode!(%{
            search: gettext("Filter keys and values"),
            copy: gettext("Copy JSON"),
            copied: gettext("Copied"),
            copy_path: gettext("Copy as {{placeholder}}"),
            expand: gettext("Expand all"),
            collapse: gettext("Collapse all"),
            no_match: gettext("Nothing matches."),
            items: gettext("items"),
            keys: gettext("keys")
          })
        }
      >
      </json-tree>
    <% end %>
    """
  end

  attr :tone, :string, default: nil
  slot :inner_block, required: true

  defp chip(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center gap-1 rounded-md px-1.5 py-0.5 font-mono text-[11px]",
      case @tone do
        "warning" -> "bg-amber-500/15 text-amber-800 dark:text-amber-200"
        "primary" -> "bg-primary/10 text-primary"
        _ -> "bg-gray-100 text-gray-700 dark:bg-slate-800 dark:text-gray-300"
      end
    ]}>
      {render_slot(@inner_block)}
    </span>
    """
  end

  attr :id, :string, default: nil
  attr :status, :string, required: true

  defp status_pill(assigns) do
    ~H"""
    <span
      id={@id}
      class={[
        "inline-flex shrink-0 items-center gap-1.5 rounded-full px-2 py-0.5 text-[11px] font-semibold uppercase tracking-wide",
        pill_class(@status)
      ]}
    >
      <.icon
        :if={@status in ["queued", "running"]}
        name="hero-arrow-path"
        class="size-3 animate-spin"
      />
      {status_label(@status)}
    </span>
    """
  end

  attr :status, :string, required: true
  attr :continued, :boolean, default: false

  defp status_dot(assigns) do
    ~H"""
    <span class={[
      "flex size-4 shrink-0 items-center justify-center rounded-full",
      dot_class(@status, @continued)
    ]}>
      <.icon :if={@status == "success"} name="hero-check-micro" class="size-3" />
      <.icon :if={@status == "error"} name="hero-x-mark-micro" class="size-3" />
      <.icon :if={@status == "skipped"} name="hero-minus-micro" class="size-3" />
    </span>
    """
  end

  defp step_name(step), do: step["label"] || step["node_type"] || step["node_id"]

  # A step can run again, or be pinned, only from data that was kept whole.
  defp whole?(%{"data" => %{"input" => _input} = data}),
    do: not Map.get(data, "truncated", false)

  defp whole?(_step), do: false

  defp format_ms(nil), do: "—"
  defp format_ms(ms) when ms < 1, do: "<1 ms"
  defp format_ms(ms) when ms < 1000, do: "#{round(ms)} ms"
  defp format_ms(ms) when ms < 60_000, do: "#{Float.round(ms / 1000, 2)} s"
  defp format_ms(ms), do: "#{div(round(ms), 60_000)} min #{rem(div(round(ms), 1000), 60)} s"

  defp result_label("failed"), do: gettext("How the run ended")
  defp result_label("waiting"), do: gettext("Where the run waits")
  defp result_label(_status), do: gettext("Result of the run")

  defp status_label("queued"), do: gettext("Queued")
  defp status_label("running"), do: gettext("Running")
  defp status_label("waiting"), do: gettext("Waiting")
  defp status_label("succeeded"), do: gettext("Succeeded")
  defp status_label("failed"), do: gettext("Failed")
  defp status_label(status), do: status

  defp pill_class("succeeded"), do: "bg-emerald-500/15 text-emerald-700 dark:text-emerald-300"
  defp pill_class("failed"), do: "bg-error/15 text-error"
  defp pill_class("waiting"), do: "bg-sky-500/15 text-sky-700 dark:text-sky-300"
  defp pill_class(_status), do: "bg-primary/10 text-primary"

  defp dot_class("success", _continued),
    do: "bg-emerald-500/20 text-emerald-700 dark:text-emerald-300"

  defp dot_class("error", true), do: "bg-amber-500/20 text-amber-700 dark:text-amber-300"
  defp dot_class("error", _continued), do: "bg-error/20 text-error"

  defp dot_class(_status, _continued),
    do: "bg-gray-200 text-gray-500 dark:bg-slate-700 dark:text-gray-400"

  defp bar_class("success", _continued), do: "bg-emerald-500/70 dark:bg-emerald-400/70"
  defp bar_class("error", true), do: "bg-amber-500/80 dark:bg-amber-400/80"
  defp bar_class("error", _continued), do: "bg-error/80"
  defp bar_class(_status, _continued), do: "bg-gray-300 dark:bg-slate-600"
end
