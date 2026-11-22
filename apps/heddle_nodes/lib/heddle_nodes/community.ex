defmodule HeddleNodes.Community do
  @moduledoc """
  The community integrations the instance installed: manifests from
  `heddlehq/integrations`, stored by `HeddleCore.Integrations`.

  Their actions become node modules at runtime, named
  `HeddleNodes.Community.<Id>.<Action>`, so the runner, the graph validator and the
  editor find them like any other node.

  A manifest whose YAML has the hash `HeddleNodes.Official` pins is official: its
  nodes say so, and show no "Not verified" warning.

  The manifests come from `:community_client` (heddle_core, through config), and are
  read again when a minute has passed, so a UI and a worker running apart agree soon
  after an install. `refresh/0` reads them at once.
  """

  alias Bobbin.Integration, as: Manifest
  alias Bobbin.Integration.Definition

  @key {__MODULE__, :state}
  @ttl_ms 60_000

  @doc "The definitions of the nodes of every community integration."
  def definitions do
    for {_id, entry} <- state().integrations, definition <- entry.definitions, do: definition
  end

  @doc "The manifest of every downloaded integration the instance runs."
  def manifests, do: for({_id, entry} <- state().integrations, do: entry.manifest)

  @doc "The community integration `id` the instance runs, or nil."
  def get(id), do: state().integrations[id]

  @doc "The module of the node called `name`, or nil."
  def get_node_module(name) do
    Enum.find_value(state().integrations, fn {_id, entry} -> entry.modules[name] end)
  end

  @doc "The credential kinds the community integrations declare."
  def credential_kinds do
    for {_id, %{manifest: %{credential: %{} = credential}}} <- state().integrations do
      HeddleNodes.Manifests.credential_kind(credential)
    end
  end

  @doc "Reads the installed manifests again, now."
  def refresh do
    previous = :persistent_term.get(@key, %{integrations: %{}})
    integrations = load(previous.integrations)
    :persistent_term.put(@key, %{integrations: integrations, at: now()})
    :ok
  end

  @doc false
  # For tests: forgets every community integration until the next read.
  def reset, do: :persistent_term.erase(@key)

  @doc "Checks a manifest, as installing it would. Returns `{:ok, manifest}` or the errors."
  def parse(yaml), do: Manifest.parse(yaml)

  defp state do
    case :persistent_term.get(@key, nil) do
      %{at: at} = state when is_integer(at) ->
        if now() - at < @ttl_ms, do: state, else: refresh_and_get()

      _missing ->
        refresh_and_get()
    end
  end

  defp refresh_and_get do
    refresh()
    :persistent_term.get(@key)
  end

  defp now, do: System.monotonic_time(:millisecond)

  defp load(previous) do
    case client() do
      nil ->
        %{}

      client ->
        client.list_community()
        |> Enum.flat_map(fn row -> entry(row, previous) end)
        |> Map.new()
    end
  rescue
    # No database yet, as while the app boots for a migration: no community nodes.
    _error -> previous
  end

  defp client do
    client = Application.get_env(:heddle_nodes, :community_client)
    if client && Code.ensure_loaded?(client), do: client
  end

  # A version that didn't change keeps its modules.
  defp entry(%{integration: id, sha256: sha} = row, previous) do
    case previous[id] do
      %{sha256: ^sha} = entry ->
        [{id, entry}]

      _other ->
        case Manifest.parse(row.manifest) do
          {:ok, %{id: ^id} = manifest} ->
            [{id, build(manifest, sha, HeddleNodes.Official.manifest?(id, row.manifest))}]

          _invalid ->
            []
        end
    end
  end

  defp build(manifest, sha, official?) do
    nodes =
      Enum.map(manifest.triggers, &{:trigger, &1, Definition.trigger_definition(manifest, &1)}) ++
        Enum.map(manifest.actions, &{:action, &1, Definition.definition(manifest, &1)})

    definitions =
      for {kind, step, definition} <- nodes do
        module = module_name(manifest, step)
        create(module, manifest, kind, step.name, definition)

        Map.merge(definition, %{
          module: module,
          community: if(official?, do: nil, else: manifest.id),
          official: official?,
          version: manifest.version
        })
      end

    %{
      manifest: manifest,
      sha256: sha,
      definitions: definitions,
      modules: Map.new(definitions, &{&1.name, &1.module})
    }
  end

  defp module_name(manifest, action) do
    Module.concat([
      __MODULE__,
      Definition.camelize(manifest.id),
      Definition.camelize(action.name)
    ])
  end

  defp create(module, manifest, kind, name, definition) do
    id = manifest.id

    body =
      quote do
        @moduledoc false
        @behaviour Bobbin.Node

        @impl true
        def definition, do: unquote(Macro.escape(definition))

        @impl true
        def handler(context, _input) do
          case HeddleNodes.Community.get(unquote(id)) do
            nil ->
              HeddleNodes.Integration.failure(
                context,
                "The integration #{unquote(id)} is no longer installed."
              )

            %{manifest: manifest} when unquote(kind) == :trigger ->
              HeddleNodes.Manifests.trigger(manifest, unquote(name), context)

            entry ->
              HeddleNodes.Manifests.run(entry.manifest, unquote(name), context)
          end
        end
      end

    previous = Code.compiler_options()[:ignore_module_conflict]
    Code.compiler_options(ignore_module_conflict: true)

    try do
      Module.create(module, body, Macro.Env.location(__ENV__))
    after
      Code.compiler_options(ignore_module_conflict: previous)
    end
  end
end
