defmodule HeddleUI.AgentChat do
  @moduledoc """
  Gives the agent what it needs to act: a short-lived API key for each message, and
  the way to the Claude Agent when that is what answers.

  The key is registered to the process of the conversation. That registration is what
  lets a run find a person to ask: a key of this kind with nobody behind it can't run
  anything.
  """

  alias HeddleAI.ClaudeAgent
  alias HeddleCore.Accounts.Scope
  alias HeddleCore.ApiKeys
  alias HeddleCore.ApiKeys.ApiKey
  alias HeddleCore.Flows.Flow
  alias HeddleCore.Settings

  @registry HeddleUI.AgentChat.Registry
  @confirmation_timeout to_timeout(minute: 5)

  def registry, do: @registry

  @doc """
  Whether the Claude Agent answers instead of the LLM.
  """
  def active?, do: Settings.claude_agent_enabled?() and ClaudeAgent.ready?()

  @doc """
  Creates the key of a run and ties it to the calling process. It reaches only the
  workspace of the flow the agent works on.
  """
  def open(%Scope{user: user}, workspace_id) do
    {:ok, %{api_key: api_key, token: token}} = ApiKeys.create_agent_key(user, workspace_id)
    {:ok, _owner} = Registry.register(@registry, api_key.id, nil)

    %{api_key: api_key, token: token}
  end

  def close(%{api_key: api_key}), do: Registry.unregister(@registry, api_key.id)

  @doc """
  Sends `content` to the agent. The key is deleted when its process ends.
  """
  def stream(%{api_key: api_key, token: token}, system, content, session) do
    client().stream_text(content,
      mcp_url: mcp_url(),
      token: token,
      session_id: session.id,
      resume?: session.started?,
      system: system,
      on_finish: fn -> ApiKeys.delete_api_key(api_key) end
    )
  end

  @doc """
  Decides whether `api_key` may run `flow` now.

  External keys answer for themselves through their scopes. An agent key waits for
  the person in the chat, and any way this can fail means no.
  """
  def confirm_run(%ApiKey{} = api_key, %Flow{} = flow) do
    confirm(api_key, flow, %{action: "run"})
  end

  @doc """
  Decides whether `api_key` may change what production runs: publish the draft of
  `flow`, or put the version numbered `number` back in production. It asks like
  `confirm_run/2`, and a person always answers it: allowing every run doesn't allow
  this.
  """
  def confirm_publish(%ApiKey{} = api_key, %Flow{} = flow, number \\ nil) do
    confirm(api_key, flow, %{action: "publish", version: number})
  end

  @doc """
  Decides whether `api_key` may replace the draft of `flow` with the version numbered
  `number`. It asks like `confirm_publish/3`.
  """
  def confirm_restore(%ApiKey{} = api_key, %Flow{} = flow, number) do
    confirm(api_key, flow, %{action: "restore", version: number})
  end

  defp confirm(api_key, flow, what) do
    if ApiKeys.agent_key?(api_key), do: ask(api_key, flow, what), else: :ok
  end

  defp ask(api_key, flow, what) do
    case Registry.lookup(@registry, api_key.id) do
      [{owner, _value}] -> wait_for_decision(owner, flow, what)
      [] -> {:error, "Nobody is available to confirm this."}
    end
  end

  defp wait_for_decision(owner, flow, what) do
    ref = Process.monitor(owner)

    question =
      Map.merge(what, %{ref: ref, reply_to: self(), flow_name: flow.name})

    send(owner, {:agent_run_confirmation, question})

    receive do
      {:agent_run_decision, ^ref, true} ->
        Process.demonitor(ref, [:flush])
        :ok

      {:agent_run_decision, ^ref, false} ->
        Process.demonitor(ref, [:flush])
        {:error, refusal(what.action)}

      {:DOWN, ^ref, :process, ^owner, _reason} ->
        {:error, "The user left before confirming."}
    after
      @confirmation_timeout ->
        Process.demonitor(ref, [:flush])
        {:error, "The user didn't confirm in time."}
    end
  end

  defp refusal("run"), do: "The user refused to run this flow."
  defp refusal("publish"), do: "The user refused to publish this flow."
  defp refusal("restore"), do: "The user refused to restore this version."

  defp mcp_url do
    port = HeddleUI.Mode.endpoint().config(:http)[:port]
    "http://127.0.0.1:#{port}/mcp"
  end

  defp client, do: Application.get_env(:heddle_ui, :claude_agent, ClaudeAgent)
end
