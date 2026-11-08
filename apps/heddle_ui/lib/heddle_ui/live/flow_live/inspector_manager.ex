defmodule HeddleUI.FlowLive.InspectorManager do
  @moduledoc """
  The run inspector of the editor: the run it shows, the steps that run took, and the
  step being looked at.

  A run started from the editor is followed as it goes: each step arrives through
  `{:execution_step, id, entry}`, see `HeddleCore.Executions.broadcast_step/2`, and the
  saved logs take their place when the run ends. Steps reach the screen in batches, so
  a loop of thousands of steps doesn't redraw it thousands of times.

  It also tells the canvas what each node did, through `run_state` and `run_steps`.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [connected?: 1, push_event: 3]

  alias HeddleCore.Executions
  alias HeddleCore.Executions.Execution

  @flush_after 120
  # More rows than this make the timeline hard to read, and only the first 500 steps
  # keep their data anyway, see `HeddleNodes.Trace`.
  @max_rows 500

  def initial_assigns, do: [inspector: nil, inspector_pending: [], inspector_flush: false]

  @doc "Shows a run that already happened, or is still going."
  def open(socket, %Execution{} = execution) do
    socket
    |> subscribe(execution)
    |> assign(:inspector, inspector(execution, execution.logs || []))
    |> assign(:inspector_pending, [])
    |> select_default()
    |> push_state()
  end

  @doc "Starts following a run the editor just queued."
  def follow(socket, %Execution{} = execution) do
    socket
    |> subscribe(execution)
    |> assign(:inspector, inspector(execution, []))
    |> assign(:inspector_pending, [])
    |> push_event("run_state", %{nodes: %{}, wires: []})
  end

  @doc "Whether the inspector shows the run with `execution_id`."
  def showing?(socket, execution_id) do
    match?(%{execution: %{id: ^execution_id}}, socket.assigns.inspector)
  end

  @doc "A step of the run being shown ended. It is shown with the next batch."
  def step(socket, execution_id, entry) do
    if showing?(socket, execution_id) do
      socket
      |> assign(:inspector_pending, [entry | socket.assigns.inspector_pending])
      |> schedule_flush()
    else
      socket
    end
  end

  @doc "Shows the steps that arrived since the last batch."
  def flush(socket) do
    pending = Enum.reverse(socket.assigns.inspector_pending)
    socket = assign(socket, :inspector_flush, false)

    case socket.assigns.inspector do
      %{execution: %{status: status}} = inspector when pending != [] ->
        steps = inspector.steps ++ pending
        status = if status == "queued", do: "running", else: status

        socket
        |> assign(:inspector, %{
          inspector
          | steps: steps,
            execution: %{inspector.execution | status: status}
        })
        |> assign(:inspector_pending, [])
        |> push_event("run_steps", %{steps: Enum.map(pending, &canvas_step/1)})

      _nothing ->
        assign(socket, :inspector_pending, [])
    end
  end

  @doc """
  The run being shown changed status. Its saved logs, the whole record of the run, take
  the place of the steps that came one by one.
  """
  def updated(socket, %Execution{} = execution) do
    if showing?(socket, execution.id) do
      shown = socket.assigns.inspector
      steps = if execution.logs in [nil, []], do: shown.steps, else: execution.logs

      inspector =
        execution
        |> inspector(steps)
        |> Map.merge(Map.take(shown, [:selected, :following, :tab, :collapsed]))

      socket
      |> assign(:inspector, inspector)
      |> assign(:inspector_pending, [])
      |> then(&if(shown.following, do: select_default(&1), else: &1))
      |> push_state()
    else
      socket
    end
  end

  @doc """
  Looks at one step, by its place in the logs, or at the result of the run. Looking at a
  step stops following the latest one.
  """
  def select(socket, :result), do: update(socket, &%{&1 | selected: :result, following: false})
  def select(socket, nil), do: socket

  def select(socket, index) when is_integer(index) do
    socket
    |> update(
      &%{&1 | selected: index, following: false, tab: default_tab(Enum.at(&1.steps, index))}
    )
    |> focus_node()
  end

  @doc """
  Looks at the last step a node took, when a person picks it on the canvas, and opens
  the panel to show it.
  """
  def select_node(socket, node_id) do
    case socket.assigns.inspector do
      %{steps: steps} ->
        steps
        |> Enum.with_index()
        |> Enum.filter(fn {step, _index} -> step["node_id"] == node_id end)
        |> List.last()
        |> case do
          {_step, index} -> socket |> update(&%{&1 | collapsed: false}) |> select(index)
          nil -> socket
        end

      nil ->
        socket
    end
  end

  def tab(socket, tab) when tab in ["output", "input", "error"],
    do: update(socket, &%{&1 | tab: tab})

  def tab(socket, _tab), do: socket

  def toggle(socket), do: update(socket, &%{&1 | collapsed: not &1.collapsed})

  def close(socket) do
    socket
    |> assign(:inspector, nil)
    |> assign(:inspector_pending, [])
    |> push_event("run_state", %{nodes: %{}, wires: []})
  end

  @doc "Reads the index of a step as the timeline sends it."
  def parse_index("result"), do: :result

  def parse_index(index) when is_binary(index) do
    case Integer.parse(index) do
      {index, ""} -> index
      _invalid -> nil
    end
  end

  @doc "The input that runs the run being shown again, as it was."
  def rerun_input(%{assigns: %{inspector: %{execution: execution}}}),
    do: {:ok, Executions.rerun_input(%Execution{input: execution.input})}

  def rerun_input(_socket), do: :error

  @doc """
  The input that runs the flow again from the step at `index`, with the context it got.
  See `Executions.replay_input/2`.
  """
  def replay_input(%{assigns: %{inspector: %{steps: steps}}}, index) when is_integer(index),
    do: Executions.replay_input(%Execution{logs: steps}, index)

  def replay_input(_socket, _index), do: {:error, :not_found}

  @doc """
  Pins what the step at `index` left to its node, for the runs from the editor to take
  instead of running it. Only a step kept whole can be pinned.
  """
  def pin(%{assigns: %{inspector: %{steps: steps}}} = socket, index) when is_integer(index) do
    case Enum.at(steps, index) do
      %{
        "node_id" => id,
        "output" => output,
        "status" => "success",
        "data" => %{"output" => data} = kept
      }
      when not is_map_key(kept, "truncated") ->
        pin = %{"output" => output, "data" => data}
        {:ok, push_event(socket, "pin_node", %{nodeId: id, pin: pin})}

      _cannot_pin ->
        :error
    end
  end

  def pin(_socket, _index), do: :error

  def unpin(socket, node_id), do: push_event(socket, "pin_node", %{nodeId: node_id, pin: nil})

  @doc "Brings the node of the step being looked at into view on the canvas."
  def focus_node(socket) do
    case selected_step(socket.assigns.inspector) do
      %{"node_id" => node_id} -> push_event(socket, "run_focus", %{nodeId: node_id})
      nil -> socket
    end
  end

  @doc "The step being looked at, or nil."
  def selected_step(%{selected: index, steps: steps}) when is_integer(index),
    do: Enum.at(steps, index)

  def selected_step(_inspector), do: nil

  @doc """
  The rows of the timeline: each step with where it starts and how long it lasts, as a
  share of the whole run.
  """
  def rows(%{steps: steps}) do
    timed =
      steps
      |> Enum.take(@max_rows)
      |> Enum.with_index()
      |> Enum.map(fn {step, index} -> {step, index, started_ms(step)} end)

    starts = for {_step, _index, ms} <- timed, ms, do: ms
    first = Enum.min(starts, fn -> 0 end)

    ends =
      for {step, _index, ms} <- timed, ms, do: ms + duration(step)

    total = max(Enum.max(ends, fn -> 0 end) - first, 0.001)

    Enum.map(timed, fn {step, index, ms} ->
      offset = if ms, do: min((ms - first) / total * 100, 99.5), else: 0.0
      width = duration(step) / total * 100

      %{
        index: index,
        step: step,
        offset: round2(offset),
        width: round2(min(max(width, 0.6), 100 - offset))
      }
    end)
  end

  @doc "How many steps the timeline leaves out."
  def hidden_rows(%{steps: steps}), do: max(length(steps) - @max_rows, 0)

  @doc "How long the run took, in ms, or nil while it hasn't started."
  def total_ms(%{execution: %{started_at: nil}}), do: nil

  def total_ms(%{execution: %{started_at: started, finished_at: finished}, steps: steps}) do
    case finished do
      %DateTime{} -> DateTime.diff(finished, started, :millisecond)
      nil -> steps |> Enum.map(&duration/1) |> Enum.sum() |> round()
    end
  end

  # What the canvas shows of a run: what each node did and the wires it took.
  defp push_state(%{assigns: %{inspector: %{steps: steps}}} = socket) do
    steps = Enum.map(steps, &canvas_step/1)

    push_event(socket, "run_state", %{
      nodes: canvas_nodes(steps),
      wires: steps |> Enum.map(&[&1.node_id, &1.output]) |> Enum.uniq()
    })
  end

  defp push_state(socket), do: socket

  defp canvas_step(entry) do
    %{
      node_id: entry["node_id"],
      status: entry["status"],
      continued: entry["continued"] == true,
      output: entry["output"],
      duration_ms: duration(entry),
      pinned: entry["pinned"] == true
    }
  end

  # The last status of a node wins, and its time is the sum of every time it ran.
  defp canvas_nodes(steps) do
    Enum.reduce(steps, %{}, fn step, acc ->
      Map.update(
        acc,
        step.node_id,
        Map.take(step, [:status, :continued, :duration_ms, :pinned]) |> Map.put(:count, 1),
        fn node ->
          %{
            node
            | status: step.status,
              continued: step.continued,
              count: node.count + 1,
              duration_ms: round2(node.duration_ms + step.duration_ms)
          }
        end
      )
    end)
  end

  # A failed run opens at the step that failed, any other at its last step.
  defp select_default(%{assigns: %{inspector: %{steps: steps}}} = socket) do
    failed = Enum.find_index(steps, &(&1["status"] == "error" and &1["continued"] != true))

    case {failed, steps} do
      {nil, []} -> update(socket, &%{&1 | selected: nil})
      {nil, steps} -> update(socket, &%{&1 | selected: length(steps) - 1, tab: "output"})
      {index, _steps} -> update(socket, &%{&1 | selected: index, tab: "error"})
    end
  end

  defp select_default(socket), do: socket

  defp default_tab(%{"status" => "error"}), do: "error"
  defp default_tab(_step), do: "output"

  defp inspector(execution, steps) do
    %{
      execution: %{
        id: execution.id,
        public_id: execution.public_id,
        flow_id: execution.flow_id,
        status: execution.status,
        error: execution.error,
        result: execution.result,
        input: execution.input,
        started_at: execution.started_at,
        finished_at: execution.finished_at
      },
      steps: steps,
      selected: nil,
      following: true,
      tab: "output",
      # It opens as a bar under the canvas, so a run doesn't take the canvas away.
      collapsed: true
    }
  end

  defp update(socket, fun) do
    case socket.assigns.inspector do
      nil -> socket
      inspector -> assign(socket, :inspector, fun.(inspector))
    end
  end

  defp schedule_flush(%{assigns: %{inspector_flush: true}} = socket), do: socket

  defp schedule_flush(socket) do
    Process.send_after(self(), :inspector_flush, @flush_after)
    assign(socket, :inspector_flush, true)
  end

  defp subscribe(socket, execution) do
    if connected?(socket), do: Executions.subscribe_to_execution(execution)
    socket
  end

  defp started_ms(%{"started_at" => at}) when is_binary(at) do
    case DateTime.from_iso8601(at) do
      {:ok, datetime, _offset} -> DateTime.to_unix(datetime, :microsecond) / 1000
      _invalid -> nil
    end
  end

  defp started_ms(_step), do: nil

  # Durations come back from JSON as integers when they are whole.
  defp round2(number), do: Float.round(number / 1, 2)

  defp duration(%{"duration_ms" => ms}) when is_number(ms), do: ms
  defp duration(%{duration_ms: ms}) when is_number(ms), do: ms
  defp duration(_step), do: 0
end
