defmodule HeddleAI.AITest do
  # Not async: it sets the LLM client and environment for the whole VM.
  use ExUnit.Case, async: false

  alias HeddleAI.AI

  defmodule FakeClient do
    def generate_text(%{id: "no-tools"}, _context, _opts) do
      {:error,
       RuntimeError.exception("registry.ollama.ai/library/no-tools does not support tools")}
    end

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

  describe "an OpenAI-compatible server" do
    @server %{
      "provider" => "openai_compatible",
      "base_url" => "http://compatible.test/v1",
      "api_key" => "",
      "model" => "qwen3:14b"
    }

    test "is called through Chat Completions at its address" do
      assert {:ok, "Hi"} = AI.run("hello", tools: [], credential: @server)

      assert_received {:generate_text, model, opts}

      assert model == %{
               provider: :openai,
               id: "qwen3:14b",
               base_url: "http://compatible.test/v1",
               extra: %{wire: %{protocol: "openai_chat"}}
             }

      assert opts[:api_key] == "none"
    end

    test "says plainly when the model doesn't use tools" do
      credential = Map.put(@server, "model", "no-tools")

      assert {:error, message} = AI.run("hello", tools: [], credential: credential)
      assert message =~ "doesn't use tools"
    end

    test "lists the models the server has, only for text and images in" do
      Application.put_env(:heddle_ai, :compatible_req_options, plug: {Req.Test, __MODULE__})
      on_exit(fn -> Application.delete_env(:heddle_ai, :compatible_req_options) end)

      Req.Test.stub(__MODULE__, fn conn ->
        assert conn.request_path == "/v1/models"
        Req.Test.json(conn, %{"data" => [%{"id" => "llama3"}, %{"id" => "gemma4:27b"}]})
      end)

      server = Map.put(@server, "base_url", "http://listing.test/v1")

      assert AI.models([credential: server], :text) == [
               %{id: "gemma4:27b", label: "gemma4:27b"},
               %{id: "llama3", label: "llama3"}
             ]

      assert AI.models([credential: server], :image) == []
    end

    test "lists nothing when the server doesn't answer" do
      Application.put_env(:heddle_ai, :compatible_req_options, plug: {Req.Test, __MODULE__})
      on_exit(fn -> Application.delete_env(:heddle_ai, :compatible_req_options) end)

      Req.Test.stub(__MODULE__, &Req.Test.transport_error(&1, :econnrefused))

      server = Map.put(@server, "base_url", "http://down.test/v1")

      assert AI.models([credential: server], :text) == []
    end
  end
end
