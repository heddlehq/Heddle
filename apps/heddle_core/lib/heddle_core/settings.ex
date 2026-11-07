defmodule HeddleCore.Settings do
  @moduledoc """
  Instance-wide settings changed from the UI.
  """

  alias HeddleCore.Repo
  alias HeddleCore.Settings.Setting

  @claude_agent "claude_agent"
  @ai_defaults "ai_defaults"

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

  @doc """
  Returns what each AI task uses when a node doesn't say, by task.

  Each task can hold a `"credential"` and a `"model"`.
  """
  def ai_defaults do
    case Repo.get(Setting, @ai_defaults) do
      %Setting{value: defaults} -> defaults
      nil -> %{}
    end
  end

  def set_ai_defaults(defaults) when is_map(defaults) do
    %Setting{}
    |> Setting.changeset(%{key: @ai_defaults, value: defaults})
    |> Repo.insert(on_conflict: {:replace, [:value, :updated_at]}, conflict_target: :key)
  end
end
