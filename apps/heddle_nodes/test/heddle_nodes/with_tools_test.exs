defmodule HeddleNodes.WithToolsTest do
  # The node registry is global: one test at a time.
  use ExUnit.Case, async: false

  alias HeddleNodes.Runner

  defmodule Thinker do
    @moduledoc "A node that brings its own model, like a package's agent."
    use Bobbin.Node

    definition do
      %{
        name: "Test: Thinker",
        title: "Thinker",
        category: :ai,
        description: "Calls its tools as a test scripts.",
        inputs: [:exec],
        outputs: ["success", "error", "tools"],
        ui_fields: [%{type: :text, name: :plan, label: "Plan", default: ""}]
      }
    end

    @impl true
    def handler(_context, _input) do
      {:with_tools, Application.fetch_env!(:heddle_nodes, :thinker_script)}
    end
  end

  @registry {HeddleNodes.Packages, :nodes}

  setup do
    previous = :persistent_term.get(@registry, nil)
    state = HeddleNodes.Packages.definitions() && :persistent_term.get(@registry)
    definition = Map.put(Thinker.definition(), :module, Thinker)

    :persistent_term.put(@registry, %{
      definitions: state.definitions ++ [definition],
      modules: Map.put(state.modules, definition.name, Thinker)
    })

    on_exit(fn ->
      if previous,
        do: :persistent_term.put(@registry, previous),
        else: :persistent_term.erase(@registry)

      Application.delete_env(:heddle_nodes, :thinker_script)
    end)
  end

  defp script(fun), do: Application.put_env(:heddle_nodes, :thinker_script, fun)

  defp graph_node(id, type, controls \\ %{}, label \\ nil) do
    %{"id" => id, "type" => type, "label" => label || type, "controls" => controls}
  end

  defp link(source, output, target) do
    %{"source" => source, "sourceOutput" => output, "target" => target, "targetInput" => "exec"}
  end

  defp flow(tools, after_nodes \\ [], after_links \\ []) do
    %{
      id: 1,
      nodes:
        [graph_node("start", "Start"), graph_node("t", "Test: Thinker") | tools] ++ after_nodes,
      connections:
        [link("start", "exec", "t") | Enum.map(tools, &link("t", "tools", &1["id"]))] ++
          after_links
    }
  end

  defp code(id, label, source) do
    graph_node(id, "Evaluate Code", %{"language" => "elixir", "code_elixir" => source}, label)
  end

  test "describes the connected nodes and runs the one called, with what the model gave" do
    script(fn tools, call ->
      send(self(), {:tools, tools})
      {:ok, shout} = call.("shout", %{"input" => "hey"})
      {:ok, "Saw #{shout}"}
    end)

    assert {:ok, context} = Runner.run(flow([code("c", "Shout", ~s(input <> "!"))]), %{})

    assert_received {:tools, [%{name: "shout", description: "Shout: " <> _, parameters: params}]}
    assert params.properties["input"]
    assert context["result"] == ~s(Saw "hey!")

    assert [%{"tool" => "shout", "ok" => true, "args" => %{"input" => "hey"}}] =
             context["tool_calls"]

    assert Enum.map(context["logs"], & &1["node_id"]) == ["start", "c", "t"]
  end

  test "a tool that fails is an answer for the model, not the end of the node" do
    script(fn _tools, call ->
      {:error, message} = call.("broken", %{})
      {:ok, "Read: #{message}"}
    end)

    script_missing = fn tools, call ->
      _ = tools
      call.("missing", %{})
    end

    assert {:ok, context} = Runner.run(flow([code("c", "Broken", ~s(raise "boom"))]), %{})
    assert context["result"] =~ "Read: "
    assert [%{"tool" => "broken", "ok" => false}] = context["tool_calls"]

    script(script_missing)
    assert {:error, _reason, "t", context} = Runner.run(flow([]), %{})
    assert context["result"] == %{"error" => "There is no tool called missing."}
  end

  test "takes the output the node names" do
    script(fn _tools, _call -> {:ok, %{"done" => true}, "error"} end)

    graph = flow([], [graph_node("ko", "Logger")], [link("t", "error", "ko")])

    assert {:ok, context} = Runner.run(graph, %{})
    assert Enum.map(context["logs"], & &1["node_id"]) == ["start", "t", "ko"]
  end

  test "a crash in the node goes down error" do
    script(fn _tools, _call -> raise "the model is down" end)

    graph = flow([], [graph_node("ko", "Logger")], [link("t", "error", "ko")])

    assert {:ok, context} = Runner.run(graph, %{})
    assert context["result"] == %{"error" => "the model is down"}
  end

  test "a Wait can't be a tool" do
    wait = graph_node("w", "Wait", %{"mode" => "duration", "amount" => "1", "unit" => "minutes"})

    script(fn _tools, call ->
      {:error, message} = call.("wait", %{})
      {:ok, message}
    end)

    assert {:ok, context} = Runner.run(flow([wait]), %{})
    assert context["result"] == "A Wait can't be a tool."
  end
end
