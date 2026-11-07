defmodule HeddleAI.HarnessTest do
  use ExUnit.Case, async: false

  alias HeddleAI.AI
  alias HeddleAI.Harness
  alias ReqLLM.Context
  alias ReqLLM.ToolCall

  defmodule Scripted do
    @behaviour HeddleAI.Harness.Model

    @impl true
    def connect(_opts), do: {:ok, :model, []}

    @impl true
    def next(:model, context, _request, on_text) do
      [reply | rest] = Process.get(:script)
      Process.put(:script, rest)
      send(self(), {:asked, context})
      play(reply, context, on_text)
    end

    defp play({:error, _reason} = error, _context, _on_text), do: error

    defp play({:calls, calls}, context, _on_text) do
      message = Context.assistant("", tool_calls: calls)
      {:ok, %{context: Context.append(context, message), tool_calls: calls}}
    end

    defp play(text, context, on_text) do
      text |> String.graphemes() |> Enum.each(on_text)
      {:ok, %{context: Context.append(context, Context.assistant(text)), tool_calls: []}}
    end
  end

  setup do
    Application.put_env(:heddle_ai, :harness_model, Scripted)
    on_exit(fn -> Application.delete_env(:heddle_ai, :harness_model) end)
  end

  defp script(replies), do: Process.put(:script, replies)

  defp call(id, name, args \\ %{}), do: ToolCall.new(id, name, Jason.encode!(args))

  defp tool(name, fun) do
    AI.tool(name, "A tool", %{"type" => "object", "properties" => %{}}, fun)
  end

  defp run(tools) do
    parent = self()

    Harness.run([%{role: "user", content: "hi"}],
      system: "Be nice",
      tools: tools,
      on_event: &send(parent, {:event, &1})
    )
  end

  test "streams the reply and returns the conversation without the instructions" do
    script(["ok"])

    assert {:ok, messages} = run([])

    assert_received {:event, {:text_delta, "o"}}
    assert_received {:event, {:text_delta, "k"}}
    assert [:user, :assistant] = Enum.map(messages, & &1.role)
  end

  test "keeps going while the model asks for tools, and reports each one" do
    script([{:calls, [call("1", "look", %{"at" => "flow"})]}, "done"])

    tools = [tool("look", fn %{"at" => "flow"} -> {:ok, "a flow"} end)]

    assert {:ok, messages} = run(tools)

    assert_received {:event, {:tool_started, %{id: "1", name: "look", args: %{"at" => "flow"}}}}

    assert_received {:event,
                     {:tool_finished, %{id: "1", name: "look", ok?: true, output: "a flow"}}}

    assert [:user, :assistant, :tool, :assistant] = Enum.map(messages, & &1.role)
  end

  test "gives the model a failed tool to read, instead of ending the turn" do
    script([{:calls, [call("1", "look")]}, "it failed, so I stopped"])

    assert {:ok, _messages} = run([tool("look", fn _args -> {:error, "no access"} end)])

    assert_received {:event, {:tool_finished, %{id: "1", ok?: false, output: output}}}
    assert output =~ "no access"
    assert_received {:event, {:text_delta, "i"}}
  end

  test "survives the model calling a tool that doesn't exist" do
    script([{:calls, [call("1", "nope")]}, "sorry"])

    assert {:ok, _messages} = run([])

    assert_received {:event, {:tool_finished, %{id: "1", name: "nope", ok?: false}}}
  end

  test "runs the tools of one reply in order" do
    script([{:calls, [call("1", "look"), call("2", "look")]}, "done"])

    assert {:ok, _messages} = run([tool("look", fn _args -> {:ok, "seen"} end)])

    assert_received {:event, {:tool_started, %{id: "1"}}}
    assert_received {:event, {:tool_finished, %{id: "1"}}}
    assert_received {:event, {:tool_started, %{id: "2"}}}
  end

  test "doesn't run the same call a third time in a row, and tells the model" do
    parent = self()
    script(List.duplicate({:calls, [call("1", "save", %{"a" => 1})]}, 3) ++ ["I got stuck."])

    tools = [tool("save", fn _args -> send(parent, :saved) && {:ok, "saved"} end)]

    assert {:ok, _messages} = run(tools)

    assert_received :saved
    assert_received :saved
    refute_received :saved
    assert_received {:event, {:tool_finished, %{ok?: true}}}
    assert_received {:event, {:tool_finished, %{ok?: true}}}
    assert_received {:event, {:tool_finished, %{ok?: false, output: "You already made" <> _rest}}}
  end

  test "lets a call repeat when something else happened between them" do
    parent = self()

    script([
      {:calls, [call("1", "test")]},
      {:calls, [call("2", "fix")]},
      {:calls, [call("3", "test")]},
      {:calls, [call("4", "fix")]},
      {:calls, [call("5", "test")]},
      "Done."
    ])

    tools = [
      tool("test", fn _args -> send(parent, :tested) && {:ok, "ran"} end),
      tool("fix", fn _args -> {:ok, "fixed"} end)
    ]

    assert {:ok, _messages} = run(tools)

    assert_received :tested
    assert_received :tested
    assert_received :tested
  end

  describe "what fits in the model" do
    test "cuts the output of older tools and keeps the recent ones whole" do
      big = String.duplicate("x", 5000)
      calls = for i <- 1..9, do: {:calls, [call("#{i}", "look", %{"page" => i})]}
      script(calls ++ ["done"])

      assert {:ok, messages} = run([tool("look", fn _args -> {:ok, big} end)])

      sizes =
        for %{role: :tool} = message <- messages do
          message.content |> Enum.map_join(& &1.text) |> String.length()
        end

      assert Enum.count(sizes, &(&1 >= 5000)) == 6
      assert Enum.count(sizes, &(&1 < 1000)) == 3
    end

    test "drops the oldest exchanges when a conversation gets too long" do
      script(["ok"])
      old = String.duplicate("old ", 100_000)

      history = [
        Context.user(old),
        Context.assistant("first answer"),
        Context.user("recent question"),
        Context.assistant("second answer")
      ]

      assert {:ok, messages} =
               Harness.run(history ++ [Context.user("now")],
                 tools: [],
                 on_event: fn _event -> :ok end
               )

      texts = Enum.map(messages, fn m -> Enum.map_join(m.content, & &1.text) end)

      refute old in texts
      assert "recent question" in texts
      assert "now" in texts
    end

    test "never drops the message it was just given" do
      script(["ok"])
      huge = String.duplicate("big ", 100_000)

      assert {:ok, [%{role: :user}, %{role: :assistant}]} =
               Harness.run([Context.user(huge)], tools: [], on_event: fn _event -> :ok end)
    end
  end

  test "stops a model that never finishes" do
    script(for i <- 1..50, do: {:calls, [call("#{i}", "look", %{"page" => i})]})

    assert {:error, "The agent took too many steps."} =
             run([tool("look", fn _args -> {:ok, "again"} end)])
  end

  test "reports a provider that fails" do
    script([{:error, RuntimeError.exception("rate limited")}])

    assert {:error, "rate limited"} = run([])
  end
end
