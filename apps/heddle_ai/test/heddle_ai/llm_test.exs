defmodule HeddleAI.LLMTest do
  use ExUnit.Case, async: true

  alias HeddleAI.LLM

  @heddle %{
    "HEDDLE_LLM_PROVIDER" => "anthropic",
    "HEDDLE_LLM_MODEL" => "claude-sonnet-5-5",
    "HEDDLE_LLM_API_KEY" => "sk-ant-test"
  }

  describe "status/1" do
    test "is not configured with an empty environment" do
      assert %{state: :not_configured, provider: nil, model: nil} = LLM.status(%{})
    end

    test "treats empty variables as unset" do
      env = %{"HEDDLE_LLM_PROVIDER" => "", "OPENAI_API_KEY" => ""}

      assert %{state: :not_configured} = LLM.status(env)
    end

    test "is ready with the three variables" do
      assert %{
               state: :ready,
               provider: "anthropic",
               model: "claude-sonnet-5-5",
               source: :heddle,
               missing: []
             } = LLM.status(@heddle)
    end

    test "names what is missing" do
      env = Map.delete(@heddle, "HEDDLE_LLM_API_KEY")

      assert %{state: :invalid, missing: ["HEDDLE_LLM_API_KEY"]} = LLM.status(env)
    end

    test "rejects a provider req_llm doesn't know" do
      env = Map.put(@heddle, "HEDDLE_LLM_PROVIDER", "not-a-provider")

      assert %{state: :invalid, missing: ["HEDDLE_LLM_PROVIDER"]} = LLM.status(env)
    end

    test "falls back to the OpenAI variables" do
      assert %{state: :ready, provider: "openai", model: "gpt-4o-mini", source: :openai_legacy} =
               LLM.status(%{"OPENAI_API_KEY" => "sk-test"})
    end

    test "honors OPENAI_MODEL in the fallback" do
      env = %{"OPENAI_API_KEY" => "sk-test", "OPENAI_MODEL" => "gpt-4.1"}

      assert %{model: "gpt-4.1"} = LLM.status(env)
    end

    test "prefers the Heddle variables over the OpenAI ones" do
      env = Map.put(@heddle, "OPENAI_API_KEY", "sk-test")

      assert %{provider: "anthropic", source: :heddle} = LLM.status(env)
    end

    test "never carries the key" do
      refute inspect(LLM.status(@heddle)) =~ "sk-ant-test"
    end
  end

  describe "credentials/1" do
    test "returns the model spec and key" do
      assert {:ok, {:anthropic, "claude-sonnet-5-5", []}, "sk-ant-test"} =
               LLM.credentials(@heddle)
    end

    test "uses the OpenAI key in the fallback" do
      assert {:ok, {:openai, "gpt-4o-mini", []}, "sk-test"} =
               LLM.credentials(%{"OPENAI_API_KEY" => "sk-test"})
    end

    test "fails when nothing is configured" do
      assert {:error, :not_configured} = LLM.credentials(%{})
    end
  end

  describe "an OpenAI-compatible server" do
    @compatible %{
      "HEDDLE_LLM_PROVIDER" => "openai_compatible",
      "HEDDLE_LLM_BASE_URL" => "http://localhost:11434/v1/",
      "HEDDLE_LLM_MODEL" => "qwen3:14b"
    }

    test "is ready from the environment without a key" do
      assert %{state: :ready, provider: "openai_compatible", missing: []} =
               LLM.status(@compatible)

      assert {:ok, {:openai_compatible, "qwen3:14b", [base_url: "http://localhost:11434/v1"]},
              "none"} = LLM.credentials(@compatible)
    end

    test "names the address when it's missing" do
      env = Map.delete(@compatible, "HEDDLE_LLM_BASE_URL")

      assert %{state: :invalid, missing: ["HEDDLE_LLM_BASE_URL"]} = LLM.status(env)
    end

    test "comes from a credential, with its key when it has one" do
      credential = %{
        "provider" => "openai_compatible",
        "base_url" => "https://openrouter.ai/api/v1",
        "api_key" => "sk-or-test",
        "model" => ""
      }

      assert {:ok, {:openai_compatible, nil, [base_url: "https://openrouter.ai/api/v1"]},
              "sk-or-test"} = LLM.connection(credential)
    end

    test "needs an address in its credential" do
      assert {:error, "The credential needs the address of the server."} =
               LLM.connection(%{"provider" => "openai_compatible", "base_url" => ""})
    end
  end

  describe "connection/1" do
    test "needs a key for every other provider" do
      assert {:error, "The credential needs an API key."} =
               LLM.connection(%{"provider" => "anthropic", "api_key" => ""})
    end
  end
end
