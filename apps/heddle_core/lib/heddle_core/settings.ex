defmodule HeddleCore.Settings do
  @moduledoc """
  Instance-wide settings changed from the UI.

  What the operator decides, such as the LLM provider, stays in the environment.
  """

  alias HeddleCore.Repo
  alias HeddleCore.Settings.Setting

  @claude_agent "claude_agent"

  def claude_agent_enabled? do
    case Repo.get(Setting, @claude_agent) do
      %Setting{value: %{"enabled" => true}} -> true
      _setting -> false
    end
  end

  def set_claude_agent_enabled(enabled) when is_boolean(enabled) do
    %Setting{}
    |> Setting.changeset(%{key: @claude_agent, value: %{"enabled" => enabled}})
    |> Repo.insert(on_conflict: {:replace, [:value, :updated_at]}, conflict_target: :key)
  end
end
