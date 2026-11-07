defmodule HeddleNodes.Runner do
  alias HeddleNodes.Agent
  alias HeddleNodes.Nodes

  @internal_keys ["flow_id", "logs"]

  @doc """
  Runs `flow` from its Start node, or from a Schedule node when it has none. The
  Schedule that fired comes in `input` as `"node_id"`.

  `:on_respond` is called with what a Respond to Webhook node answers.
  """
  def run(flow, input \\ %{}, opts \\ []) do
    input = normalize_input(input)

    if start_node = start_node(flow, input) do
      initial_context =
        input
        |> Map.delete("node_id")
        |> Map.merge(%{
          "flow_id" => flow.id,
          "logs" => []
        })

      case execute_node(start_node, initial_context, graph(flow, opts)) do
        {:ok, execution_result} -> {:ok, execution_result}
        {:error, reason, node_id} -> {:error, reason, node_id}
      end
    else
      {:error, "No Start node found", nil}
    end
  end

  defp start_node(flow, %{"node_id" => node_id}) do
    Enum.find(flow.nodes, &(to_string(&1["id"]) == to_string(node_id))) || start_node(flow, %{})
  end

  defp start_node(flow, _input) do
    Enum.find(flow.nodes, &node_type?(&1, "Start")) ||
      Enum.find(flow.nodes, &node_type?(&1, "Schedule"))
  end

  defp node_type?(node, type), do: node["type"] == type || node["label"] == type

  defp graph(flow, opts) do
    %{
      nodes: flow.nodes,
      connections: flow.connections,
      on_respond: Keyword.get(opts, :on_respond, fn _response -> :ok end)
    }
  end

  defp execute_node(node, context, flow) do
    node_type = node["type"] || node["label"]
    definition = Nodes.get_node(node_type)

    if definition do
      module = get_node_module(node_type)

      context = if is_map(context), do: context, else: %{"result" => context}
      control_keys = Map.keys(node["controls"] || %{}) -- preserved_control_keys(node_type)
      node_context = Map.merge(context, node["controls"] || %{})

      step = %{
        node: node,
        type: node_type,
        context: context,
        control_keys: control_keys,
        flow: flow
      }

      try do
        case apply(module, :handler, [node_context, nil]) do
          {:ok, result, output_name} ->
            follow(result, to_string(output_name), step)

          {:ok, result} ->
            follow(result, first_output(definition), step)

          {:result, value} ->
            follow(Map.put(context, "result", value), first_output(definition), step)

          {:respond, response, result} ->
            flow.on_respond.(response)
            follow(result, first_output(definition), step)

          {:each, items} ->
            run_each(items, step)

          {:agent, request} ->
            run_agent(request, step)

          {:error, reason} ->
            error_context =
              finish_node(
                Map.put(context, "result", reason),
                context,
                control_keys,
                node,
                node_type,
                "error",
                :error,
                format_reason(reason)
              )

            case connections_from(flow, node, "error") do
              [] -> {:error, reason, to_string(node["id"])}
              connections -> process_connections(connections, error_context, flow)
            end
        end
      rescue
        e ->
          {:error, Exception.message(e), to_string(node["id"])}
      catch
        kind, reason ->
          formatted_reason = Exception.format(kind, reason, __STACKTRACE__)
          {:error, formatted_reason, to_string(node["id"])}
      end
    else
      {:ok, context}
    end
  end

  defp first_output(definition), do: to_string(List.first(definition[:outputs]) || "exec")

  # An error nobody handles fails the run. Ending as a success would hide it.
  defp follow(result, "error", step) do
    case connections_from(step.flow, step.node, "error") do
      [] ->
        {:error, error_message(result), to_string(step.node["id"])}

      connections ->
        process_connections(connections, finish_step(result, "error", step), step.flow)
    end
  end

  defp follow(result, output_name, step) do
    result = finish_step(result, output_name, step)

    step.flow
    |> connections_from(step.node, output_name)
    |> process_connections(result, step.flow)
  end

  defp error_message(%{"result" => %{"error" => message}}) when is_binary(message), do: message
  defp error_message(%{"result" => reason}), do: reason
  defp error_message(_result), do: "This step failed."

  defp finish_step(result, output_name, step) do
    finish_node(
      result,
      step.context,
      step.control_keys,
      step.node,
      step.type,
      output_name,
      :success
    )
  end

  defp connections_from(flow, node, output_name) do
    Enum.filter(flow.connections, fn connection ->
      connection["source"] == node["id"] && connection["sourceOutput"] == output_name
    end)
  end

  defp run_agent(request, step) do
    tools =
      step.flow
      |> connections_from(step.node, "tools")
      |> Enum.flat_map(fn connection ->
        Enum.filter(step.flow.nodes, &(&1["id"] == connection["target"]))
      end)

    run_tool = fn node, input ->
      execute_node(node, tool_context(step.context, input), step.flow)
    end

    case Agent.run(request, step.context["flow_id"], tools, run_tool) do
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
    base = finish_step(step.context, "item", step)
    branch = connections_from(step.flow, step.node, "item")

    items
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, base["logs"], []}, fn {item, index}, {:ok, logs, results} ->
      iteration =
        Map.merge(base, %{"logs" => logs, "item" => item, "index" => index, "result" => item})

      case process_connections(branch, iteration, step.flow) do
        {:ok, finished} -> {:cont, {:ok, finished["logs"], [finished["result"] | results]}}
        {:error, reason, node_id} -> {:halt, {:error, reason, node_id}}
      end
    end)
    |> case do
      {:ok, logs, results} ->
        results = Enum.reverse(results)
        done = Map.merge(base, %{"logs" => logs, "results" => results, "result" => results})

        step.flow
        |> connections_from(step.node, "done")
        |> process_connections(done, step.flow)

      error ->
        error
    end
  end

  defp finish_node(result, previous_context, control_keys, node, node_type, output_name, status) do
    finish_node(result, previous_context, control_keys, node, node_type, output_name, status, nil)
  end

  defp finish_node(
         result,
         previous_context,
         control_keys,
         node,
         node_type,
         output_name,
         status,
         error
       ) do
    result
    |> normalize_context()
    |> remove_node_controls(previous_context, control_keys)
    |> append_execution_log(node, node_type, output_name, status, error)
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

  defp append_execution_log(context, node, node_type, output_name, status, error) do
    log_entry =
      %{
        "node_id" => to_string(node["id"]),
        "node_type" => node_type,
        "status" => Atom.to_string(status),
        "output" => to_string(output_name),
        "context_keys" => context |> Map.drop(@internal_keys) |> Map.keys() |> Enum.sort()
      }
      |> maybe_put_error(error)

    logs = Map.get(context, "logs", [])
    Map.put(context, "logs", logs ++ [log_entry])
  end

  defp maybe_put_error(log_entry, nil), do: log_entry
  defp maybe_put_error(log_entry, error), do: Map.put(log_entry, "error", error)

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)

  defp preserved_control_keys("Output"), do: ["status"]
  defp preserved_control_keys(_node_type), do: []

  defp process_connections(connections, context, flow) do
    Enum.reduce_while(connections, {:ok, context}, fn conn, {:ok, acc_context} ->
      target_node = Enum.find(flow.nodes, fn n -> n["id"] == conn["target"] end)

      if target_node do
        case execute_node(target_node, acc_context, flow) do
          {:ok, next_ctx} -> {:cont, {:ok, next_ctx}}
          {:error, r, n} -> {:halt, {:error, r, n}}
        end
      else
        {:cont, {:ok, acc_context}}
      end
    end)
  end

  def run_from_webhook(flow, webhook_request, opts \\ []) do
    webhook_node =
      Enum.find(flow.nodes, fn node ->
        (node["type"] || node["label"]) == "Webhook"
      end)

    if webhook_node do
      initial_context = %{
        "flow_id" => flow.id,
        "logs" => [],
        "body" => webhook_request["body"],
        "headers" => webhook_request["headers"],
        "method" => webhook_request["method"],
        "query_params" => webhook_request["query_params"],
        "request_path" => webhook_request["path"]
      }

      execute_node(webhook_node, initial_context, graph(flow, opts))
    else
      {:error, "No Webhook node found in flow", nil}
    end
  end

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
