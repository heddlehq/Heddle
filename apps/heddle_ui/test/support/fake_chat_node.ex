defmodule HeddleUI.FakeChatNode do
  @moduledoc """
  A package's trigger people talk to, for the tests of chats, panels and the agent
  tools: it answers each message at once with "You said: ...", keeping the
  conversations in memory. `register/0` adds it to the nodes, until the test ends.
  """

  use Bobbin.Node

  @registry {HeddleNodes.Packages, :nodes}
  @table __MODULE__

  definition do
    %{
      name: "Test: Talk",
      title: "Talk",
      category: :agents,
      color: "bg-sky-500/15",
      icon: "hero-user-circle-solid",
      description: "Talks back.",
      show: true,
      inputs: [],
      outputs: [:exec],
      ui_fields: [%{type: :text, name: :name, label: "Name", default: ""}]
    }
  end

  @impl true
  def handler(context, _input), do: {:ok, context, "exec"}

  @impl true
  def chat_message(_workspace_id, _controls, _conversation, "fail"), do: {:error, "It can't now."}

  def chat_message(workspace_id, controls, conversation, text) do
    key = {workspace_id, controls["name"], conversation}
    messages = history(key) ++ [%{role: :visitor, text: text}, %{role: :agent, text: "You said: " <> text}]
    :ets.insert(@table, {key, messages})
    {:ok, :sent}
  end

  @impl true
  def chat_history(workspace_id, controls, conversation),
    do: history({workspace_id, controls["name"], conversation})

  @impl true
  def panel(_workspace_id, controls) do
    [
      %{
        title: "Instances",
        columns: ["key", "state"],
        rows: [%{"key" => "main", "state" => %{"agent" => controls["name"]}}]
      }
    ]
  end

  defp history(key) do
    case :ets.lookup(@table, key) do
      [{_key, messages}] -> messages
      [] -> []
    end
  end

  @doc "Adds this node to the nodes Heddle knows, and a table for its conversations."
  def register do
    if :ets.whereis(@table) == :undefined,
      do: :ets.new(@table, [:named_table, :public, :set, {:heir, Process.whereis(:init), nil}])

    previous = :persistent_term.get(@registry, nil)
    _loaded = HeddleNodes.Packages.definitions()
    state = :persistent_term.get(@registry)
    definition = Map.put(definition(), :module, __MODULE__)

    :persistent_term.put(@registry, %{
      definitions: state.definitions ++ [definition],
      modules: Map.put(state.modules, definition.name, __MODULE__)
    })

    fn ->
      if previous,
        do: :persistent_term.put(@registry, previous),
        else: :persistent_term.erase(@registry)
    end
  end
end
