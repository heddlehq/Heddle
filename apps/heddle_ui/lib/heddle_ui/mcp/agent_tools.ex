defmodule HeddleUI.MCP.AgentTools do
  @moduledoc """
  Offers the MCP tools to the LLM.

  Each one runs with the caller's frame, so the model can only do what the API key
  that started the chat can.
  """

  require Logger

  alias Anubis.Server.Response
  alias HeddleAI.AI
  alias HeddleCore.Flows
  alias HeddleUI.MCP.Tools

  @tools [
    {"list_flows", Tools.ListFlows},
    {"get_flow", Tools.GetFlow},
    {"create_flow", Tools.CreateFlow},
    {"update_flow", Tools.UpdateFlow},
    {"list_nodes", Tools.ListNodes},
    {"list_executions", Tools.ListExecutions},
    {"get_execution", Tools.GetExecution}
  ]

  # What is left of a long result is enough to read, and it stays in the conversation.
  @max_output 20_000

  @doc """
  Builds the tools of the agent, which tests flows by itself and waits for the result.
  Running one goes through `HeddleUI.AgentChat.confirm_run/2`.
  """
  def for_agent(frame) do
    Enum.map([{"test_flow", Tools.TestFlow} | @tools], &to_ai_tool(&1, frame))
  end

  @doc """
  Builds the tools of one chat through MCP.

  `run_flow` is there too, but it runs nothing: it sends `{ref, :run_requested, request}`
  to the caller, and running stays a decision of the person on the other end.
  """
  def build(frame, ref) do
    [run_request_tool(frame, ref, self()) | Enum.map(@tools, &to_ai_tool(&1, frame))]
  end

  defp to_ai_tool({name, module}, frame) do
    schema = schema(module)

    AI.tool(name, module.__description__(), schema, fn args ->
      call(module, args, schema, frame)
    end)
  end

  defp run_request_tool(frame, ref, parent) do
    module = Tools.RunFlow
    schema = schema(module)

    AI.tool("run_flow", module.__description__(), schema, fn args ->
      id = to_string(args["flow_id"] || args[:flow_id])

      case Flows.get_flow(frame.assigns.current_scope, id) do
        nil ->
          {:error, "Flow #{id} was not found."}

        flow ->
          input = args["input"] || args[:input]
          send(parent, {ref, :run_requested, %{flow_id: flow.id, name: flow.name, input: input}})
          {:ok, "The user will be asked to confirm. Stop here and tell them."}
      end
    end)
  end

  defp schema(module), do: module.input_schema() |> Map.delete("$schema")

  defp call(module, args, schema, frame) do
    params = params(args, schema)

    case Enum.reject(Map.get(schema, "required", []), &Map.has_key?(args_by_name(args), &1)) do
      [] -> execute(module, params, frame)
      missing -> {:error, "Missing: #{Enum.join(missing, ", ")}"}
    end
  end

  # What the model sends isn't validated on the way in, and a wrong shape must come
  # back to it as an error it can correct, not end the chat.
  defp execute(module, params, frame) do
    {:reply, %Response{} = response, _frame} = module.execute(params, frame)

    text =
      response.content
      |> Enum.map_join("\n", &Map.get(&1, "text", ""))
      |> String.slice(0, @max_output)

    if response.isError, do: {:error, text}, else: {:ok, text}
  rescue
    error ->
      Logger.warning("MCP tool #{inspect(module)} failed: #{Exception.message(error)}")
      {:error, "These arguments didn't work. Check them against the tool's schema."}
  end

  # Only names from the schema become atoms, whatever the model sends.
  defp params(args, schema) do
    args = args_by_name(args)

    for {name, _definition} <- Map.get(schema, "properties", %{}),
        Map.has_key?(args, name),
        into: %{} do
      {String.to_existing_atom(name), args[name]}
    end
  end

  defp args_by_name(args), do: Map.new(args, fn {key, value} -> {to_string(key), value} end)
end
