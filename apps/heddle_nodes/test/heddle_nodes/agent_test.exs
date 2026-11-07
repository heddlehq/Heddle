defmodule HeddleNodes.AgentTest do
  use ExUnit.Case, async: false

  alias HeddleNodes.Runner

  defmodule Model do
    @moduledoc "Stands in for the LLM: a test scripts what it does with the tools."
    def tool(name, description, schema, fun) do
      %{name: name, description: description, schema: schema, fun: fun}
    end

    def run(messages, opts) do
      send(self(), {:llm, messages, opts})
      Application.fetch_env!(:heddle_nodes, :model_script).(messages, opts)
    end

    def generate_image(_prompt, _opts), do: {:ok, {String.duplicate(<<0>>, 6000), "image/png"}}
    def check(_capability, _opts), do: :ok
  end

  defmodule Settings do
    def ai_defaults, do: %{}
  end

  defmodule Memory do
    def load(flow_id, key), do: Application.get_env(:heddle_nodes, {:memory, flow_id, key}, [])

    def save(flow_id, key, messages) do
      Application.put_env(:heddle_nodes, {:memory, flow_id, key}, messages)
    end
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
    script(fn _messages, _opts -> {:ok, "Olá"} end)

    on_exit(fn ->
      Enum.each(previous, fn
        {key, nil} -> Application.delete_env(:heddle_nodes, key)
        {key, value} -> Application.put_env(:heddle_nodes, key, value)
      end)

      Application.delete_env(:heddle_nodes, {:memory, 1, "ana"})
    end)
  end

  defp script(fun), do: Application.put_env(:heddle_nodes, :model_script, fun)

  defp graph_node(id, type, controls \\ %{}, label \\ nil) do
    %{"id" => id, "type" => type, "label" => label || type, "controls" => controls}
  end

  defp link(source, output, target) do
    %{"source" => source, "sourceOutput" => output, "target" => target, "targetInput" => "exec"}
  end

  defp agent_flow(controls, nodes \\ [], connections \\ []) do
    %{
      id: 1,
      nodes: [graph_node("start", "Start"), graph_node("agent", "AI Agent", controls) | nodes],
      connections: [link("start", "exec", "agent") | connections]
    }
  end

  defp tool(opts, name), do: Enum.find(opts[:tools], &(&1.name == name))

  describe "the prompt" do
    test "sends it with the context filled in and keeps the reply" do
      graph = agent_flow(%{"prompt" => "Translate {{word}}", "system" => "Be {{tone}}"})

      assert {:ok, context} = Runner.run(graph, %{"word" => "hi", "tone" => "brief"})

      assert context["result"] == "Olá"
      assert_received {:llm, [%{role: "user", content: "Translate hi"}], opts}
      assert opts[:system] == "Be brief"
      assert opts[:tools] == []
    end

    test "passes the model, temperature and step limit" do
      graph =
        agent_flow(%{
          "prompt" => "Hi",
          "model" => "gpt-x",
          "temperature" => "0.2",
          "max_steps" => "3"
        })

      assert {:ok, _context} = Runner.run(graph, %{})
      assert_received {:llm, _messages, opts}
      assert opts[:model] == "gpt-x"
      assert opts[:temperature] == 0.2
      assert opts[:max_steps] == 3
    end

    test "leaves out what isn't set" do
      assert {:ok, _context} = Runner.run(agent_flow(%{"prompt" => "Hi", "system" => " "}), %{})
      assert_received {:llm, _messages, opts}
      assert opts[:system] == nil
      assert opts[:model] == nil
      assert opts[:temperature] == nil
    end

    test "takes the error output when the model fails" do
      script(fn _messages, _opts -> {:error, "No LLM provider is configured."} end)

      graph =
        agent_flow(%{"prompt" => "Hi"}, [graph_node("ko", "Logger")], [
          link("agent", "error", "ko")
        ])

      assert {:ok, context} = Runner.run(graph, %{})
      assert context["result"] == %{"error" => "No LLM provider is configured."}
      assert Enum.any?(context["logs"], &(&1["node_id"] == "ko"))
    end

    test "fails the run with nothing to ask, when nobody handles the error" do
      assert {:error, "The prompt is empty.", "agent", _context} =
               Runner.run(agent_flow(%{"prompt" => "  "}), %{})

      refute_received {:llm, _, _}
    end
  end

  describe "tools" do
    defp with_tool(tool_node) do
      agent_flow(%{"prompt" => "Go"}, [tool_node], [link("agent", "tools", tool_node["id"])])
    end

    test "offers the connected nodes, asking only for the fields left blank" do
      node =
        graph_node(
          "http",
          "HTTP Request",
          %{"method" => "POST", "url" => "", "body" => "", "headers" => "{}"},
          "Call the CRM!"
        )

      assert {:ok, _context} = Runner.run(with_tool(node), %{})
      assert_received {:llm, _messages, opts}

      assert [%{name: "call_the_crm", description: description, schema: schema}] = opts[:tools]
      assert description =~ "Call the CRM!"
      assert description =~ "HTTP endpoint"
      assert Map.keys(schema.properties) |> Enum.sort() == ["body", "url"]
      assert Enum.sort(schema.required) == ["body", "url"]
    end

    test "never offers a credential or code" do
      node =
        graph_node("s", "Slack: Send Message", %{
          "credential" => "",
          "channel" => "#ops",
          "text" => "",
          "thread_ts" => "1.1"
        })

      assert {:ok, _context} = Runner.run(with_tool(node), %{})
      assert_received {:llm, _messages, opts}
      assert [%{schema: schema}] = opts[:tools]
      assert Map.keys(schema.properties) == ["text"]

      code = graph_node("c", "Evaluate Code", %{"language" => "elixir", "code_elixir" => ""})

      assert {:ok, _context} = Runner.run(with_tool(code), %{})
      assert_received {:llm, _messages, opts}
      assert [%{schema: schema}] = opts[:tools]
      assert Map.keys(schema.properties) == ["input"]
    end

    test "keeps a generated file out of what the model reads" do
      node = graph_node("i", "AI: Generate Image", %{"credential" => "", "prompt" => "A cat"})

      assert {:ok, _context} = Runner.run(with_tool(node), %{})
      assert_received {:llm, _messages, opts}
      assert [%{fun: tool}] = opts[:tools]
      assert {:ok, output} = tool.(%{})
      assert output =~ "image/png"
      refute output =~ "AAAA"
    end

    test "offers a select as a choice" do
      node =
        graph_node("h", "HTTP Request", %{
          "method" => "",
          "url" => "x",
          "headers" => "{}",
          "body" => "x"
        })

      assert {:ok, _context} = Runner.run(with_tool(node), %{})
      assert_received {:llm, _messages, opts}
      assert [%{schema: %{properties: %{"method" => %{enum: methods}}}}] = opts[:tools]
      assert "POST" in methods
    end

    test "runs the node with the model's values and gives it the result" do
      code =
        graph_node("c", "Evaluate Code", %{
          "language" => "elixir",
          "code_elixir" => "input <> \"!\""
        })

      script(fn _messages, opts ->
        {:ok, seen} = tool(opts, "evaluate_code").fun.(%{"input" => "hey"})
        {:ok, "Saw #{seen}"}
      end)

      assert {:ok, context} = Runner.run(with_tool(code), %{})

      assert context["result"] == ~s(Saw "hey!")

      assert [%{"tool" => "evaluate_code", "ok" => true, "args" => %{"input" => "hey"}}] =
               context["tool_calls"]

      assert Enum.map(context["logs"], & &1["node_id"]) == ["start", "c", "agent"]
    end

    test "accepts the model's values under atom keys" do
      code = graph_node("c", "Evaluate Code", %{"language" => "elixir", "code_elixir" => "input"})

      script(fn _messages, opts ->
        {:ok, seen} = tool(opts, "evaluate_code").fun.(%{input: "x"})
        {:ok, seen}
      end)

      assert {:ok, %{"result" => ~s("x")}} = Runner.run(with_tool(code), %{})
    end

    test "tells the model when a tool fails, and goes on" do
      code =
        graph_node("c", "Evaluate Code", %{
          "language" => "elixir",
          "code_elixir" => ~s(raise "boom")
        })

      script(fn _messages, opts ->
        assert {:error, message} = tool(opts, "evaluate_code").fun.(%{})
        {:ok, "It failed: #{message}"}
      end)

      assert {:ok, context} = Runner.run(with_tool(code), %{})
      assert context["result"] =~ "boom"
      assert [%{"ok" => false}] = context["tool_calls"]
    end

    test "a tool runs what comes after it" do
      first =
        graph_node("c", "Evaluate Code", %{"language" => "elixir", "code_elixir" => "1 + 1"})

      next =
        graph_node("d", "Evaluate Code", %{"language" => "elixir", "code_elixir" => "result * 10"})

      graph =
        agent_flow(%{"prompt" => "Go"}, [first, next], [
          link("agent", "tools", "c"),
          link("c", "exec", "d")
        ])

      script(fn _messages, opts -> tool(opts, "evaluate_code").fun.(%{}) end)

      assert {:ok, %{"result" => "20"}} = Runner.run(graph, %{})
    end

    test "a tool that isn't called doesn't run" do
      code = graph_node("c", "Evaluate Code", %{"language" => "elixir", "code_elixir" => "1"})

      assert {:ok, context} = Runner.run(with_tool(code), %{})
      refute Enum.any?(context["logs"], &(&1["node_id"] == "c"))
      assert context["tool_calls"] == []
    end

    test "gives repeated names a way apart" do
      a = graph_node("a", "Logger", %{}, "Log")
      b = graph_node("b", "Logger", %{}, "Log")

      graph =
        agent_flow(%{"prompt" => "Go"}, [a, b], [
          link("agent", "tools", "a"),
          link("agent", "tools", "b")
        ])

      assert {:ok, _context} = Runner.run(graph, %{})
      assert_received {:llm, _messages, opts}
      names = Enum.map(opts[:tools], & &1.name)
      assert length(Enum.uniq(names)) == 2
    end
  end

  describe "JSON output" do
    test "gives the next nodes a real value" do
      script(fn _messages, _opts -> {:ok, ~s(```json\n{"score": 9}\n```)} end)

      assert {:ok, context} =
               Runner.run(agent_flow(%{"prompt" => "Rate", "output" => "json"}), %{})

      assert context["result"] == %{"score" => 9}
      assert_received {:llm, _messages, opts}
      assert opts[:system] =~ "JSON"
    end

    test "takes the error output when the reply isn't JSON" do
      script(fn _messages, _opts -> {:ok, "Sure thing"} end)

      graph =
        agent_flow(%{"prompt" => "Rate", "output" => "json"}, [graph_node("ko", "Logger")], [
          link("agent", "error", "ko")
        ])

      assert {:ok, context} = Runner.run(graph, %{})

      assert context["result"]["error"] =~ "not JSON"
      assert context["result"]["reply"] == "Sure thing"
    end
  end

  describe "memory" do
    test "remembers the conversation under its key" do
      graph = agent_flow(%{"prompt" => "{{text}}", "memory_key" => "{{user}}"})

      assert {:ok, _context} = Runner.run(graph, %{"text" => "I'm Ana", "user" => "ana"})
      assert {:ok, _context} = Runner.run(graph, %{"text" => "Who am I?", "user" => "ana"})

      assert_received {:llm, [%{role: "user", content: "I'm Ana"}], _opts}
      assert_received {:llm, messages, _opts}

      assert messages == [
               %{role: "user", content: "I'm Ana"},
               %{role: "assistant", content: "Olá"},
               %{role: "user", content: "Who am I?"}
             ]
    end

    test "keeps nothing without a key" do
      assert {:ok, _context} = Runner.run(agent_flow(%{"prompt" => "Hi"}), %{})
      assert Memory.load(1, "") == []
    end

    test "doesn't remember a failed run" do
      script(fn _messages, _opts -> {:error, "down"} end)

      graph = agent_flow(%{"prompt" => "Hi", "memory_key" => "ana"})

      assert {:error, "down", "agent", _context} = Runner.run(graph, %{})
      assert Memory.load(1, "ana") == []
    end
  end
end
