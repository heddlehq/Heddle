defmodule HeddleUI.FlowLive.AgentStepsTest do
  # Not async: it swaps the LLM the nodes call.
  use ExUnit.Case, async: false

  alias HeddleNodes.Runner
  alias HeddleUI.FlowLive.AgentSteps

  defmodule Model do
    def tool(name, description, schema, fun),
      do: %{name: name, description: description, schema: schema, fun: fun}

    def run(_messages, opts) do
      tool = Enum.find(opts[:tools], &(&1.name == "evaluate_code"))
      {:ok, _seen} = tool.fun.(%{"input" => "ORD-7"})
      {:ok, "Order ORD-7 is late."}
    end

    def check(_capability, _opts), do: :ok
  end

  defmodule Settings do
    def ai_defaults, do: %{}
  end

  defmodule Memory do
    def load(_flow_id, _key), do: []
    def save(_flow_id, _key, _messages), do: :ok
  end

  setup do
    previous =
      Map.new(
        [:llm_client, :agent_memory, :ai_settings],
        &{&1, Application.get_env(:heddle_nodes, &1)}
      )

    Application.put_env(:heddle_nodes, :llm_client, Model)
    Application.put_env(:heddle_nodes, :ai_settings, Settings)
    Application.put_env(:heddle_nodes, :agent_memory, Memory)

    on_exit(fn ->
      Enum.each(previous, fn
        {key, nil} -> Application.delete_env(:heddle_nodes, key)
        {key, value} -> Application.put_env(:heddle_nodes, key, value)
      end)
    end)
  end

  defp node(id, type, controls, label \\ nil),
    do: %{"id" => id, "type" => type, "label" => label || type, "controls" => controls}

  defp wire(source, output, target),
    do: %{
      "source" => source,
      "sourceOutput" => output,
      "target" => target,
      "targetInput" => "exec"
    }

  defp flow do
    %{
      id: 1,
      nodes: [
        node("start", "Start", %{}),
        node("agent", "AI Agent", %{"prompt" => "Is order {{order}} late?"}, "Check order"),
        node("look", "Evaluate Code", %{
          "language" => "elixir",
          "code_elixir" => "input <> \" late\""
        })
      ],
      connections: [wire("start", "exec", "agent"), wire("agent", "tools", "look")]
    }
  end

  test "asks to turn what the agent did into steps, with its tools, arguments and results" do
    assert {:ok, context} = Runner.run(flow(), %{"order" => "ORD-7"})
    steps = context["logs"]
    index = Enum.find_index(steps, &(&1["node_id"] == "agent"))

    assert AgentSteps.eligible?(Enum.at(steps, index))
    refute AgentSteps.eligible?(Enum.at(steps, 0))

    assert {:ok, request} = AgentSteps.request(flow(), steps, index, "run-42")

    assert request =~ ~s|Turn the AI Agent "Check order" (node `agent`)|
    assert request =~ "in run run-42"
    assert request =~ "Is order {{order}} late?"
    assert request =~ ~s(1. `evaluate_code` with `{"input":"ORD-7"}`)
    assert request =~ "It returned: `ORD-7 late`"
    assert request =~ "Order ORD-7 is late."
    assert request =~ "{{placeholder}}"
    assert request =~ "Tell me the plan before you change the flow."
  end

  test "refuses a step that isn't an agent, or whose node left the flow" do
    assert {:ok, context} = Runner.run(flow(), %{"order" => "ORD-7"})
    steps = context["logs"]
    index = Enum.find_index(steps, &(&1["node_id"] == "agent"))

    assert AgentSteps.request(flow(), steps, 0, "run") == :error

    gone = %{flow() | nodes: Enum.reject(flow().nodes, &(&1["id"] == "agent"))}
    assert AgentSteps.request(gone, steps, index, "run") == :error
  end
end
