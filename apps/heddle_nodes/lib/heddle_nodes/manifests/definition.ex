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

    Integration.definition(service, action.name, action.description, ui_fields(action))
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
