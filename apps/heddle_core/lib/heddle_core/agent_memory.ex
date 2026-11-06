defmodule HeddleCore.AgentMemory do
  @moduledoc """
  What an AI Agent node remembers between runs, per flow and key.
  """

  use Ecto.Schema

  alias HeddleCore.Repo

  # Old messages cost tokens on every run, and the model gains little from them.
  @max_messages 40

  schema "agent_memories" do
    field :flow_id, :id
    field :key, :string
    field :messages, {:array, :map}, default: []

    timestamps(type: :utc_datetime)
  end

  def load(flow_id, key) do
    case Repo.get_by(__MODULE__, flow_id: flow_id, key: key) do
      nil -> []
      memory -> Enum.map(memory.messages, &%{role: &1["role"], content: &1["content"]})
    end
  end

  def save(flow_id, key, messages) do
    now = DateTime.utc_now(:second)

    kept =
      messages
      |> Enum.take(-@max_messages)
      |> Enum.map(&Map.new(&1, fn {k, v} -> {to_string(k), v} end))

    Repo.insert_all(
      __MODULE__,
      [%{flow_id: flow_id, key: key, messages: kept, inserted_at: now, updated_at: now}],
      on_conflict: [set: [messages: kept, updated_at: now]],
      conflict_target: [:flow_id, :key]
    )

    :ok
  end
end
