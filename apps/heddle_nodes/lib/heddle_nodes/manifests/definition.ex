defmodule HeddleNodes.Manifests.Definition do
  @moduledoc false
  # What `HeddleNodes.Manifests` needs while it compiles, so it lives apart.

  alias HeddleNodes.Integration

  @doc "The module of `action` in `manifest`."
  def module_name(manifest, action) do
    Module.concat([HeddleNodes.Manifests, Macro.camelize(manifest.id), camelize(action.name)])
  end

  @doc false
  def camelize(name) do
    name
    |> String.split(~r/[^A-Za-z0-9]+/, trim: true)
    |> Enum.map_join(fn <<first::utf8, rest::binary>> ->
      String.upcase(<<first::utf8>>) <> rest
    end)
  end

  @doc "The node definition of `action`."
  def definition(manifest, action) do
    service = %{
      title: manifest.name,
      category: String.to_atom(manifest.category),
      credential: manifest.credential && manifest.credential.kind,
      icon: manifest.icon
    }

    service
    |> Integration.definition(action.name, action.description, ui_fields(action))
    |> Map.put(:integration, manifest.id)
  end

  @trigger_color "bg-emerald-500/15 text-emerald-700 dark:text-emerald-300"

  @doc """
  The node definition of `trigger`: a node a flow starts from, once for each new item
  the service returns, see `HeddleNodes.Manifests.poll/3`.
  """
  def trigger_definition(manifest, trigger) do
    name = "#{manifest.name}: #{trigger.name}"
    kind = manifest.credential && manifest.credential.kind
    credential = if kind, do: [Integration.credential_field(kind)], else: []

    %{
      name: name,
      title: name,
      category: String.to_atom(manifest.category),
      color: @trigger_color,
      description: trigger.description,
      icon: manifest.icon,
      inputs: [],
      outputs: [:exec],
      show: true,
      ui_fields: credential ++ ui_fields(trigger),
      integration: manifest.id,
      poll: %{trigger: trigger.name, every: trigger.poll.every}
    }
  end

  defp ui_fields(action) do
    Enum.map(action.fields, fn field ->
      %{
        type: if(field.type == "select", do: :select, else: String.to_atom(field.type)),
        name: String.to_atom(field.name),
        label: field.label,
        default: field.default
      }
      |> put_options(field.options)
      |> Map.update!(:type, &if(&1 == :number, do: :text, else: &1))
    end)
  end

  defp put_options(field, nil), do: field

  defp put_options(field, options) do
    Map.put(
      field,
      :options,
      Enum.map(options, &%{label: to_string(&1["label"]), value: to_string(&1["value"])})
    )
  end
end
