defmodule HeddleCore.Settings do
  @moduledoc """
  Instance-wide settings changed from the UI.
  """

  alias HeddleCore.Repo
  alias HeddleCore.Settings.Setting

  @claude_agent "claude_agent"
  @ai_defaults "ai_defaults"
  @terminal "terminal"
  @claude_binary "claude_binary"

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

  def terminal_enabled? do
    case Repo.get(Setting, @terminal) do
      %Setting{value: %{"enabled" => true}} -> true
      _setting -> false
    end
  end

  def set_terminal_enabled(enabled) when is_boolean(enabled) do
    put(@terminal, %{"enabled" => enabled})
  end

  @doc "Returns the path of the claude program chosen in the AI page, if any."
  def claude_binary do
    case Repo.get(Setting, @claude_binary) do
      %Setting{value: %{"path" => path}} when path != "" -> path
      _setting -> nil
    end
  end

  @doc "Saves the path of the claude program. An empty one goes back to finding it."
  def set_claude_binary(path) when is_binary(path) do
    put(@claude_binary, %{"path" => String.trim(path)})
  end

  defp put(key, value) do
    %Setting{}
    |> Setting.changeset(%{key: key, value: value})
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
