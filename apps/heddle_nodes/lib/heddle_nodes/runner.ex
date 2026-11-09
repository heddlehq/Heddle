defmodule HeddleNodes.Runner do
  @moduledoc """
  Runs a flow, one node after the other, in the process that calls it.

  A run ends in one of three ways:

    * `{:ok, context}` when it finished;
    * `{:error, reason, node_id, context}` when a node failed and nothing handled it,
      with what the context held then, so the failure can be understood afterwards;
    * `{:wait, paused}` when a `Wait` paused it. `paused` is plain data, to be saved
      and given to `resume/4` later, and it holds what was left to run: the nodes
      after the ones that were running, the items a `For Each` hadn't reached, and the
      branches waiting at a `Merge`.

  A `Merge` holds each branch that reaches it, in the context, and goes on once every
  connection to it has arrived. When the run has nothing else to do, the merges still
  holding branches go on with the ones that arrived, in the order they began to wait,
  so a branch that a `Condition` never took doesn't hold the run forever.

  Each step leaves an entry in the `"logs"` of the context, with how long it took, how
  many tries it needed and, see `HeddleNodes.Trace`, the context it got and what it
  changed. A node's settings, see `Heddle.Graph.Settings`, say how often it tries again
  and what its failure does to the run.
  """

  alias Heddle.Graph
  alias Heddle.Graph.Settings
  alias HeddleNodes.Agent
  alias HeddleNodes.Nodes
  alias HeddleNodes.Trace

  # Branches waiting at a Merge: `[%{"node_id" => id, "results" => [...]}]`, in the
  # order they began to wait. It travels in the context so it is saved with a pause.
  @merging "_merging"
  @run_only [@merging, "resume_url"]
  @internal_keys ["flow_id", "workspace_id", "logs" | @run_only]
  @run_keys ["node_id", "section_id", "replay_from", "debug"]
  @drain %{"kind" => "drain"}

  @doc """
  Runs `flow` from its Start node, or from its first entry node when it has none, like
  a Schedule or a Webhook. The Schedule that fired comes in `input` as `"node_id"`. A
  run with `"trigger" => "error"`, which a failed flow starts, begins at the Error
  Trigger, and one with `"trigger" => "subflow"`, which a Subflow node starts, at the
  Subflow Trigger, or the Start node when it has none.

  With `"section_id"` in `input`, it runs only that section, from each node nothing in
  it leads to, one after the other. See `Heddle.Graph.Section`.

  With `"replay_from"` in `input`, it runs from that node, with the rest of `input` as
  the context, which is how the editor runs a flow again from one of its steps.

  Options:

    * `:on_respond` is called with what a Respond to Webhook node answers.
    * `:on_step` is called with the log entry of each step as it ends.
    * `:resume_url` is the address that resumes a `Wait` on a call. A flow with a
      `Wait` reads it as `{{resume_url}}`, to send it before it waits.
    * `:debug`, when true, takes the data pinned to a node instead of running it. Only
      runs started from the editor set it.
    * `:sleep` waits between the tries of a step, `Process.sleep/1` by default.
  """
  def run(flow, input \\ %{}, opts \\ []) do
    Trace.start()
    input = normalize_input(input)
    section_id = input["section_id"] || replay_section(flow, input["replay_from"])
    graph = graph(flow, section_id)
    state = run_state(graph, flow, opts, section_id)

    case first_nodes(graph, input, section_id) do
      {:ok, nodes} ->
        context = initial_context(flow, Map.drop(input, @run_keys), state, opts)

        nodes
        |> run_nodes(context, state)
        |> then(&continue([@drain], &1, state))
        |> finish(state)

      {:error, message} ->
        {:error, message, nil, %{}}
    end
  end

  @doc """
  Runs `flow` from its Webhook node, as if `webhook_request` had reached it.

  With `:section`, it takes the Webhook of that section, as `run/3` does. It takes the
  other options of `run/3`.
  """
  def run_from_webhook(flow, webhook_request, opts \\ []) do
    Trace.start()
    section_id = opts[:section]
    graph = graph(flow, section_id)
    state = run_state(graph, flow, opts, section_id)

    if webhook_node = List.first(Graph.of_type(graph, "Webhook")) do
      request = %{
        "body" => webhook_request["body"],
        "headers" => webhook_request["headers"],
        "method" => webhook_request["method"],
        "query_params" => webhook_request["query_params"],
        "request_path" => webhook_request["path"]
      }

      webhook_node
      |> execute_node(initial_context(flow, request, state, opts), state)
      |> then(&continue([@drain], &1, state))
      |> finish(state)
    else
      {:error, "No Webhook node found in flow", nil, %{}}
    end
  end

  @doc """
  Goes on with a run a `Wait` paused, from what `run/3` returned in `{:wait, paused}`.

  `resumption` says what ended the wait: `%{"by" => "time"}`, `%{"by" => "timeout"}`,
  or `%{"by" => "call", "request" => request}`, which the `Wait` passes on as its
  `result`. It takes the options of `run/3`, and returns what it does.

  It reads the flow as it is now, so a node deleted while the run waited is skipped.
  """
  def resume(flow, %{"wait" => wait, "context" => context} = paused, resumption, opts \\ []) do
    Trace.start()
    section_id = paused["section_id"]
    state = run_state(graph(flow, section_id), flow, opts, section_id)

    resumed =
      case Graph.get(state.graph, wait["node_id"]) do
        nil -> {:ok, context}
        node -> wake(node, context, resumption, state)
      end

    paused
    |> Map.get("frames", [])
    |> continue(resumed, state)
    |> finish(state)
  end

  defp wake(node, context, %{"by" => "call"} = resumption, state) do
    context
    |> Map.put("result", resumption["request"])
    |> follow("exec", step(node, context, state))
  end

  defp wake(node, context, %{"by" => "timeout"}, state) do
    follow(context, "timeout", step(node, context, state))
  end

  defp wake(node, context, _time, state), do: follow(context, "exec", step(node, context, state))

  defp graph(flow, nil), do: Graph.new(flow)
  defp graph(flow, section_id), do: Graph.new(flow, section: section_id)

  # A node of a manual section runs only with its section.
  defp replay_section(_flow, nil), do: nil

  defp replay_section(flow, node_id) do
    if Graph.get(Graph.new(flow), node_id) do
      nil
    else
      flow
      |> Graph.sections()
      |> Enum.find_value(fn section -> node_id in section.nodes && section.id end)
    end
  end

  defp first_nodes(graph, %{"replay_from" => node_id}, _section_id) when is_binary(node_id) do
    case Graph.get(graph, node_id) do
      nil -> {:error, "This node is no longer in the flow."}
      node -> {:ok, [node]}
    end
  end

  defp first_nodes(graph, _input, section_id) when not is_nil(section_id) do
    case {Graph.section(graph), Graph.entries(graph)} do
      {nil, _entries} -> {:error, "This section was not found."}
      {_section, []} -> {:error, "This section has no node to start from."}
      {_section, entries} -> {:ok, entries}
    end
  end

  defp first_nodes(graph, input, nil) do
    cond do
      start_node = start_node(graph, input) ->
        {:ok, [start_node]}

      Graph.holds_back?(graph) ->
        {:error, "Every node this flow can start from is in a manual section."}

      true ->
        {:error, "No Start node found"}
    end
  end

  defp start_node(graph, %{"node_id" => node_id}) do
    Graph.get(graph, node_id) || start_node(graph, %{})
  end

  defp start_node(graph, %{"trigger" => "error"}) do
    List.first(Graph.of_type(graph, "Error Trigger")) || start_node(graph, %{})
  end

  defp start_node(graph, %{"trigger" => "subflow"}) do
    List.first(Graph.of_type(graph, "Subflow Trigger")) || start_node(graph, %{})
  end

  defp start_node(graph, _input) do
    List.first(Graph.of_type(graph, "Start")) || Enum.find(graph.nodes, &entry_node?/1)
  end

  # Nothing can lead to a node without inputs, so a flow can only begin there.
  defp entry_node?(node) do
    match?(%{inputs: []}, Nodes.get_node(node.type))
  end

  defp run_state(graph, flow, opts, section_id) do
    %{
      graph: graph,
      section_id: section_id,
      flow_id: flow.id,
      workspace_id: Map.get(flow, :workspace_id),
      on_respond: Keyword.get(opts, :on_respond, fn _response -> :ok end),
      on_step: Keyword.get(opts, :on_step, fn _entry -> :ok end),
      debug: Keyword.get(opts, :debug, false) == true,
      sleep: Keyword.get(opts, :sleep, &Process.sleep/1)
    }
  end

  defp initial_context(flow, values, state, opts) do
    context =
      Map.merge(values, %{
        "flow_id" => flow.id,
        "workspace_id" => Map.get(flow, :workspace_id),
        "logs" => []
      })

    case {opts[:resume_url], Graph.of_type(state.graph, "Wait")} do
      {url, [_wait | _more]} when is_binary(url) -> Map.put(context, "resume_url", url)
      _no_wait -> context
    end
  end

  defp finish({:ok, context}, _state), do: {:ok, Map.drop(context, @run_only)}

  defp finish({:error, reason, node_id, context}, _state),
    do: {:error, reason, node_id, Map.drop(context, @run_only)}

  defp finish({:wait, wait, context, frames}, state) do
    {:wait,
     %{
       "wait" => wait,
       "context" => context,
       "frames" => frames,
       "section_id" => state.section_id
     }}
  end

  # What is left of a run after the step that returned `result`, innermost first.
  defp continue([], result, _state), do: result

  defp continue(frames, {:wait, wait, context, inner}, _state),
    do: {:wait, wait, context, inner ++ frames}

  defp continue(_frames, {:error, _reason, _node_id, _context} = error, _state), do: error

  defp continue([frame | rest], {:ok, context}, state) do
    continue(rest, run_frame(frame, context, state), state)
  end

  defp run_frame(%{"kind" => "nodes", "ids" => ids}, context, state) do
    ids
    |> Enum.flat_map(&List.wrap(Graph.get(state.graph, &1)))
    |> run_nodes(context, state)
  end

  defp run_frame(%{"kind" => "each"} = frame, context, state) do
    case Graph.get(state.graph, frame["node_id"]) do
      nil ->
        {:ok, context}

      node ->
        each(
          %{node: node, branch: Graph.next(state.graph, node, "item"), base: frame["base"]},
          frame["items"],
          frame["index"],
          context["logs"],
          [context["result"] | frame["results"]],
          state
        )
    end
  end

  defp run_frame(%{"kind" => "drain"}, context, state), do: drain(context, state)

  defp run_nodes([], context, _state), do: {:ok, context}

  defp run_nodes([node | rest], context, state) do
    case execute_node(node, context, state) do
      {:ok, next_context} -> run_nodes(rest, next_context, state)
      {:wait, wait, paused, frames} -> {:wait, wait, paused, frames ++ nodes_frame(rest)}
      {:error, _reason, _node_id, _context} = error -> error
    end
  end

  defp nodes_frame([]), do: []
  defp nodes_frame(nodes), do: [%{"kind" => "nodes", "ids" => Enum.map(nodes, & &1.id)}]

  defp execute_node(%{type: "Merge"} = node, context, state) when is_map(context) do
    arrive(node, context, state)
  end

  defp execute_node(node, context, state), do: run_node(node, context, state)

  # A branch that reaches a Merge stops there until the last one arrives.
  defp arrive(node, context, state) do
    merging = Map.get(context, @merging) || []
    held = Enum.find_value(merging, [], &(&1["node_id"] == node.id && &1["results"]))
    results = held ++ [context["result"]]

    if length(results) >= length(Graph.incoming(state.graph, node)) do
      context
      |> Map.put(@merging, Enum.reject(merging, &(&1["node_id"] == node.id)))
      |> Map.put("result", results)
      |> then(&run_node(node, &1, state))
    else
      {:ok, Map.put(context, @merging, hold(merging, node.id, results))}
    end
  end

  # A merge that was already waiting keeps its place in line.
  defp hold(merging, node_id, results) do
    held = %{"node_id" => node_id, "results" => results}

    if Enum.any?(merging, &(&1["node_id"] == node_id)) do
      Enum.map(merging, &if(&1["node_id"] == node_id, do: held, else: &1))
    else
      merging ++ [held]
    end
  end

  # When nothing else is left, the first merge still waiting goes on with what it has.
  defp drain(context, state) do
    case Map.get(context, @merging) || [] do
      [] ->
        {:ok, context}

      [%{"node_id" => id, "results" => results} | rest] ->
        context = Map.put(context, @merging, rest)

        result =
          case Graph.get(state.graph, id) do
            nil -> {:ok, context}
            node -> run_node(node, Map.put(context, "result", results), state)
          end

        continue([@drain], result, state)
    end
  end

  defp step(node, context, state) do
    %{
      node: node,
      type: node.type,
      context: context,
      control_keys: Map.keys(node.controls) -- preserved_control_keys(node.type),
      outputs: node_outputs(node.type),
      flow: state,
      started_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      started: System.monotonic_time(:microsecond),
      attempts: 1,
      retry_errors: [],
      pinned: false
    }
  end

  defp node_outputs(type) do
    case Nodes.get_node(type) do
      nil -> []
      definition -> Enum.map(definition[:outputs] || [], &to_string/1)
    end
  end

  defp run_node(node, context, flow) do
    if definition = Nodes.get_node(node.type) do
      context = if is_map(context), do: context, else: %{"result" => context}
      step = step(node, context, flow)

      try do
        case pin(node, flow) do
          %{"output" => output, "data" => data} ->
            follow(Map.merge(context, data), output, %{step | pinned: true})

          nil ->
            {outcome, step} = attempt(get_node_module(node.type), step, 1)
            handle(outcome, definition, step)
        end
      rescue
        e -> fail(step.context, Exception.message(e), step)
      catch
        kind, reason -> fail(step.context, Exception.format(kind, reason, __STACKTRACE__), step)
      end
    else
      {:ok, context}
    end
  end

  defp pin(%{settings: %Settings{pin: pin}}, %{debug: true}), do: pin
  defp pin(_node, _flow), do: nil

  # A step that fails runs again while its settings give it tries.
  defp attempt(module, step, number) do
    # What a node or a field sets can't move a run to another flow or workspace, where
    # it would read their credentials and memory.
    node_context =
      step.context
      |> Map.merge(step.node.controls)
      |> Map.merge(%{"flow_id" => step.flow.flow_id, "workspace_id" => step.flow.workspace_id})

    outcome = call(module, node_context)
    settings = step.node.settings

    case failure(outcome) do
      {:failed, message} when number <= settings.retries ->
        step.flow.sleep.(Settings.delay(settings, number + 1))
        attempt(module, %{step | retry_errors: step.retry_errors ++ [message]}, number + 1)

      _outcome ->
        {outcome, %{step | attempts: number}}
    end
  end

  defp call(module, node_context) do
    apply(module, :handler, [node_context, nil])
  rescue
    e -> {:crash, Exception.message(e)}
  catch
    kind, reason -> {:crash, Exception.format(kind, reason, __STACKTRACE__)}
  end

  defp failure({:error, reason}), do: {:failed, format_reason(reason)}
  defp failure({:crash, message}), do: {:failed, message}

  defp failure({:ok, result, output}) when output in [:error, "error"],
    do: {:failed, format_reason(error_message(normalize_context(result)))}

  defp failure(_outcome), do: :ok

  defp handle(outcome, definition, step) do
    context = step.context
    node = step.node

    case outcome do
      {:ok, result, output_name} ->
        follow(result, to_string(output_name), step)

      {:ok, result} ->
        follow(result, first_output(definition), step)

      {:result, value} ->
        follow(Map.put(context, "result", value), first_output(definition), step)

      {:respond, response, result} ->
        step.flow.on_respond.(response)
        follow(result, first_output(definition), step)

      {:each, items} ->
        run_each(items, step)

      {:agent, request} ->
        run_agent(request, step)

      {:wait, wait} ->
        {:wait, Map.put(wait, "node_id", node.id), context, []}

      {:error, reason} ->
        fail(Map.put(context, "result", reason), reason, step)

      {:crash, message} ->
        fail(context, message, step)
    end
  end

  # What a failure does once no try is left, see `Heddle.Graph.Settings`. An error
  # nobody handles fails the run: ending as a success would hide it.
  defp fail(error_context, reason, step) do
    message = format_reason(reason)

    case {step.node.settings.on_error, continue_output(step)} do
      {"continue", output} when not is_nil(output) ->
        result =
          error_context
          |> Map.put("result", %{"error" => message})
          |> finish_node(step, output, :error, %{"error" => message, "continued" => true})

        {nodes, result} = next_nodes(step.flow.graph, step.node, output, result)
        run_nodes(nodes, result, step.flow)

      _stop ->
        finished = finish_node(error_context, step, "error", :error, %{"error" => message})

        case next_nodes(step.flow.graph, step.node, "error", finished) do
          {[], finished} -> {:error, reason, step.node.id, finished}
          {nodes, finished} -> run_nodes(nodes, finished, step.flow)
        end
    end
  end

  # The output a failure goes on through when the node continues.
  defp continue_output(step) do
    Enum.find(step.outputs, &(&1 not in ["error", "tools"]))
  end

  defp first_output(definition), do: to_string(List.first(definition[:outputs]) || "exec")

  defp follow(result, "error", step) do
    result
    |> normalize_context()
    |> fail(error_message(normalize_context(result)), step)
  end

  defp follow(result, output_name, step) do
    result = finish_step(result, output_name, step)
    {nodes, result} = next_nodes(step.flow.graph, step.node, output_name, result)

    run_nodes(nodes, result, step.flow)
  end

  # A branch that reaches a manual section stops there, and says so in the logs.
  defp next_nodes(graph, node, output, context) do
    held_back =
      for held <- Graph.held_back(graph, node, output) do
        %{
          "node_id" => held.id,
          "node_type" => held.type,
          "status" => "skipped",
          "message" => "In a manual section: it runs only when the section is run."
        }
      end

    {Graph.next(graph, node, output), Map.update(context, "logs", held_back, &(&1 ++ held_back))}
  end

  defp error_message(%{"result" => %{"error" => message}}) when is_binary(message), do: message
  defp error_message(%{"result" => reason}), do: reason
  defp error_message(_result), do: "This step failed."

  defp finish_step(result, output_name, step),
    do: finish_node(result, step, output_name, :success)

  defp run_agent(request, step) do
    tools = Graph.next(step.flow.graph, step.node, "tools")

    run_tool = fn node, input ->
      case execute_node(node, tool_context(step.context, input), step.flow) do
        {:wait, _wait, context, _frames} ->
          {:error, "A Wait can't be the tool of an AI Agent.", node.id, context}

        result ->
          result
      end
    end

    case Agent.run(request, step.flow.flow_id, tools, run_tool) do
      {:ok, value, calls, logs} ->
        step.context
        |> agent_result(value, calls, logs)
        |> follow("success", step)

      {:error, error, calls, logs} ->
        error = if is_binary(error), do: %{"error" => error}, else: error

        step.context
        |> agent_result(error, calls, logs)
        |> follow("error", step)
    end
  end

  defp tool_context(context, input) do
    context
    |> Map.put("logs", [])
    |> Map.put("input", input)
  end

  defp agent_result(context, value, calls, logs) do
    Map.merge(context, %{
      "result" => value,
      "tool_calls" => calls,
      "logs" => Map.get(context, "logs", []) ++ logs
    })
  end

  # What a branch changes stays in that iteration, apart from its result and logs.
  defp run_each(items, step) do
    {branch, base} =
      next_nodes(step.flow.graph, step.node, "item", finish_step(step.context, "item", step))

    loop = %{node: step.node, branch: branch, base: base, started: step}
    each(loop, items, 0, base["logs"], [], step.flow)
  end

  # `results` is in reverse, as it is built.
  # The loop leaves a step of its own when it ends, through `done`, timed from when it
  # began. A loop a Wait paused is timed from when it went on.
  defp each(loop, [], _index, logs, results, state) do
    results = Enum.reverse(results)
    step = Map.get(loop, :started) || step(loop.node, loop.base, state)

    done =
      loop.base
      |> Map.merge(%{"logs" => logs, "results" => results, "result" => results})
      |> finish_node(%{step | context: loop.base, control_keys: []}, "done", :success)

    {nodes, done} = next_nodes(state.graph, loop.node, "done", done)

    run_nodes(nodes, done, state)
  end

  # A Merge inside the branch waits for that iteration's branches only.
  defp each(loop, [item | rest], index, logs, results, state) do
    iteration =
      Map.merge(loop.base, %{
        "logs" => logs,
        "item" => item,
        "index" => index,
        "result" => item,
        @merging => []
      })

    case continue([@drain], run_nodes(loop.branch, iteration, state), state) do
      {:ok, finished} ->
        each(loop, rest, index + 1, finished["logs"], [finished["result"] | results], state)

      {:wait, wait, context, frames} ->
        frame = %{
          "kind" => "each",
          "node_id" => loop.node.id,
          "base" => Map.delete(loop.base, "logs"),
          "items" => rest,
          "index" => index + 1,
          "results" => results
        }

        {:wait, wait, context, frames ++ [frame]}

      {:error, _reason, _node_id, _context} = error ->
        error
    end
  end

  defp finish_node(result, step, output_name, status, extra \\ %{}) do
    result
    |> normalize_context()
    |> remove_node_controls(step.context, step.control_keys)
    |> append_execution_log(step, output_name, status, extra)
  end

  defp normalize_context(%{} = context), do: context
  defp normalize_context(value), do: %{"result" => value}

  defp remove_node_controls(context, previous_context, control_keys) do
    Enum.reduce(control_keys, context, fn key, acc ->
      if Map.has_key?(previous_context, key) do
        Map.put(acc, key, previous_context[key])
      else
        Map.delete(acc, key)
      end
    end)
  end

  defp append_execution_log(context, step, output_name, status, extra) do
    visible = Map.drop(context, @internal_keys)

    log_entry =
      %{
        "node_id" => step.node.id,
        "node_type" => step.type,
        "status" => Atom.to_string(status),
        "output" => to_string(output_name),
        "context_keys" => visible |> Map.keys() |> Enum.sort(),
        "started_at" => step.started_at,
        "duration_ms" => duration(step)
      }
      |> put_if("label", step.node.label, step.node.label not in [nil, "", step.type])
      |> put_if("attempts", step.attempts, step.attempts > 1)
      |> put_if("retry_errors", step.retry_errors, step.retry_errors != [])
      |> put_if("pinned", true, step.pinned)
      |> Map.put("data", Trace.step(Map.drop(step.context, @internal_keys), visible))
      |> Map.merge(extra)

    step.flow.on_step.(log_entry)
    Map.update(context, "logs", [log_entry], &(&1 ++ [log_entry]))
  end

  defp duration(step) do
    Float.round((System.monotonic_time(:microsecond) - step.started) / 1000, 2)
  end

  defp put_if(map, key, value, true), do: Map.put(map, key, value)
  defp put_if(map, _key, _value, false), do: map

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)

  defp preserved_control_keys("Output"), do: ["status"]
  defp preserved_control_keys(_node_type), do: []

  defp normalize_input(input) when is_map(input) do
    Map.new(input, fn {key, value} -> {to_string(key), value} end)
  end

  defp normalize_input(_input), do: %{}

  defp get_node_module("Evaluate Code"), do: HeddleNodes.Nodes.Eval
  defp get_node_module("HTTP Request"), do: HeddleNodes.Nodes.HttpRequest

  defp get_node_module(name) do
    Nodes.get_node_module(name)
  end
end
