defmodule HeddleAI.AITest do
  # Not async: it sets the LLM client and environment for the whole VM.
  use ExUnit.Case, async: false

  alias HeddleAI.AI

  defmodule FakeClient do
    def generate_text(model, context, opts) do
      send(self(), {:generate_text, model, opts})

      {:ok,
       %ReqLLM.Response{
         id: "1",
         model: "m",
         context: context,
         message: ReqLLM.Context.assistant("Hi")
       }}
    end

    def stream_text(model, messages, opts) do
      send(self(), {:stream_text, model, messages, opts})

      case messages do
        [%{content: "fail"}] ->
          {:error, RuntimeError.exception("provider rejected the request")}

        _messages ->
          {:ok,
           %{
             stream: [
               %{type: :thinking, text: "hmm"},
               %{type: :content, text: "Hel"},
               %{type: :content, text: "lo"},
               %{type: :meta, text: nil}
             ]
           }}
      end
    end
  end

  @variables ~w(HEDDLE_LLM_PROVIDER HEDDLE_LLM_MODEL HEDDLE_LLM_API_KEY OPENAI_API_KEY OPENAI_MODEL)

  setup do
    previous_env = System.get_env() |> Map.take(@variables)
    previous_client = Application.get_env(:heddle_ai, :llm_client)

    Enum.each(@variables, &System.delete_env/1)
    System.put_env("OPENAI_API_KEY", "sk-test")
    Application.put_env(:heddle_ai, :llm_client, FakeClient)

    on_exit(fn ->
      Enum.each(@variables, &System.delete_env/1)
      System.put_env(previous_env)

      if previous_client,
        do: Application.put_env(:heddle_ai, :llm_client, previous_client),
        else: Application.delete_env(:heddle_ai, :llm_client)
    end)
  end

  describe "stream_text/2" do
    test "streams only the text deltas" do
      assert {:ok, %{stream: stream}} = AI.stream_text([%{role: "user", content: "hello"}])

      assert Enum.to_list(stream) == [{:text_delta, "Hel"}, {:text_delta, "lo"}]
    end

    test "sends the resolved model, key and system prompt" do
      messages = [%{role: "user", content: "hello"}]

      AI.stream_text(messages, system: "be brief")

      assert_received {:stream_text, {:openai, "gpt-4o-mini", []}, ^messages, opts}
      assert opts[:api_key] == "sk-test"
      assert opts[:system_prompt] == "be brief"
    end

    test "turns a provider failure into an error event" do
      assert {:ok, %{stream: stream}} = AI.stream_text([%{role: "user", content: "fail"}])

      assert Enum.to_list(stream) == [{:error, "provider rejected the request"}]
    end

    test "reports a missing configuration in the stream" do
      System.delete_env("OPENAI_API_KEY")

      assert {:ok, %{stream: stream}} = AI.stream_text([%{role: "user", content: "hello"}])

      assert [{:error, "No AI provider is set up." <> _rest}] = Enum.to_list(stream)
      refute_received {:stream_text, _model, _messages, _opts}
    end
  end

  describe "run/2" do
    test "uses the instance's model by default" do
      assert {:ok, "Hi"} = AI.run("hello", tools: [])

      assert_received {:generate_text, {:openai, "gpt-4o-mini", []}, opts}
      refute Keyword.has_key?(opts, :temperature)
    end

    test "takes a model and a temperature" do
      assert {:ok, "Hi"} = AI.run("hello", tools: [], model: "gpt-x", temperature: 0.2)

      assert_received {:generate_text, {:openai, "gpt-x", []}, opts}
      assert opts[:temperature] == 0.2
    end

    test "stops at the step limit" do
      assert {:error, message} = AI.run("hello", tools: [], max_steps: 0)
      assert message =~ "too many steps"
    end
  end
end
