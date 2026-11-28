defmodule HeddleNodes.BobbinHostTest do
  use ExUnit.Case, async: false

  alias HeddleNodes.BobbinHost
  alias HeddleNodes.Usage

  defmodule Model do
    def connect(opts) do
      send(self(), {:connect, opts})

      case opts[:credential] do
        %{"broken" => true} -> {:error, "The credential needs an API key."}
        _other -> {:ok, {:openai, opts[:model] || "gpt-default", []}, [tools: [], api_key: "k"]}
      end
    end

    def check(_capability, _opts), do: :ok
  end

  defmodule Settings do
    def ai_defaults,
      do: %{"text" => %{"credential" => "", "model" => "from-ai-page"}}
  end

  defmodule Credentials do
    def fetch(7, "mine", "ai"), do: {:ok, %{"provider" => "openai", "api_key" => "k"}}
    def fetch(7, "broken", "ai"), do: {:ok, %{"broken" => true}}
    def fetch(_workspace, _name, _kind), do: {:error, :not_found}
  end

  setup do
    previous =
      Map.new(
        [:llm_client, :ai_settings, :credentials_client],
        &{&1, Application.get_env(:heddle_nodes, &1)}
      )

    Application.put_env(:heddle_nodes, :llm_client, Model)
    Application.put_env(:heddle_nodes, :ai_settings, Settings)
    Application.put_env(:heddle_nodes, :credentials_client, Credentials)

    on_exit(fn ->
      Enum.each(previous, fn
        {key, nil} -> Application.delete_env(:heddle_nodes, key)
        {key, value} -> Application.put_env(:heddle_nodes, key, value)
      end)
    end)
  end

  describe "ai_connection/2" do
    test "uses the node's credential and model, and leaves the tools out" do
      context = %{"workspace_id" => 7, "credential" => "mine", "model" => "gpt-x"}

      assert {:ok, %{model: {:openai, "gpt-x", []}, options: options}} =
               BobbinHost.ai_connection(context, :text)

      assert options == [api_key: "k"]
      assert_received {:connect, opts}
      assert opts[:credential] == %{"provider" => "openai", "api_key" => "k"}
      assert opts[:tools] == []
    end

    test "without a credential or a model, the AI page decides" do
      assert {:ok, %{model: {:openai, "from-ai-page", []}}} =
               BobbinHost.ai_connection(%{"workspace_id" => 7}, :text)
    end

    test "says when the credential is gone" do
      context = %{"workspace_id" => 7, "credential" => "gone"}

      assert {:error, "The credential gone doesn't exist anymore. Pick another one."} =
               BobbinHost.ai_connection(context, :text)
    end

    test "says what the provider can't do" do
      context = %{"workspace_id" => 7, "credential" => "broken"}

      assert {:error, "The credential needs an API key."} =
               BobbinHost.ai_connection(context, :text)
    end
  end

  test "record_usage/1 adds to the step running" do
    ref = Usage.enter()
    :ok = BobbinHost.record_usage(%{input_tokens: 10, output_tokens: 4, total_cost: 0.002})
    :ok = Bobbin.Host.record_usage(%{input_tokens: 1, output_tokens: 1})

    assert Usage.leave(ref) == %{
             "calls" => 2,
             "input_tokens" => 11,
             "output_tokens" => 5,
             "cost" => 0.002
           }
  end
end
