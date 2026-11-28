defmodule HeddleNodes.Packages do
  @moduledoc """
  The integrations Heddle was built with: Mix packages from heddlehq/integrations,
  written with `Bobbin.Service`. Each names its node modules in its app env,
  `bobbin_nodes`, and the modules made from its manifests in `bobbin_integrations`
  (see `Bobbin.Integration.Nodes`).
  """

  @key {__MODULE__, :nodes}

  @doc "The definitions of every node of the packages."
  def definitions, do: state().definitions

  @doc "The module of the node called `name`, or nil."
  def get_node_module(name), do: state().modules[name]

  @doc "The manifests the packages carry, for their triggers and credentials."
  def manifests do
    for app <- apps(),
        module <- Application.get_env(app, :bobbin_integrations, []),
        do: module.manifest()
  end

  @doc "The `priv/docs.json` of each package that has one, for `HeddleNodes.Docs`."
  def docs_files do
    for app <- apps(),
        file = Application.app_dir(app, "priv/docs.json"),
        File.exists?(file),
        do: file
  end

  @doc """
  The flows the packages offer to start from, from the JSON files each one lists in
  `bobbin_templates`, by path in its app: `name`, `description`, `nodes`,
  `connections`, and the same texts in other languages under `i18n`, like
  `"i18n": {"pt-BR": {"name": ..., "description": ...}}`. Each gets an `id`, its app and
  file name, and its `package`.
  """
  def templates do
    for app <- template_apps(),
        path <- Application.get_env(app, :bobbin_templates, []),
        template = read_template(app, path),
        template != nil do
      template
    end
  end

  defp template_apps do
    for {app, _description, _version} <- Application.loaded_applications(),
        Application.get_env(app, :bobbin_templates) not in [nil, []],
        do: app
  end

  defp read_template(app, path) do
    file = if Path.type(path) == :absolute, do: path, else: Application.app_dir(app, path)

    with {:ok, text} <- File.read(file),
         {:ok, %{"name" => _, "nodes" => nodes} = template} when is_list(nodes) <-
           Jason.decode(text) do
      template
      |> Map.put("id", "#{app}/#{Path.basename(path, ".json")}")
      |> Map.put("package", to_string(app))
      |> Map.put_new("connections", [])
    else
      _other -> nil
    end
  end

  defp state do
    case :persistent_term.get(@key, nil) do
      nil ->
        state = load()
        :persistent_term.put(@key, state)
        state

      state ->
        state
    end
  end

  defp load do
    definitions =
      for app <- apps(), module <- modules(app) do
        Map.put(module.definition(), :module, module)
      end

    %{definitions: definitions, modules: Map.new(definitions, &{&1.name, &1.module})}
  end

  defp modules(app) do
    integrations = Application.get_env(app, :bobbin_integrations, [])
    Enum.flat_map(integrations, & &1.nodes()) ++ Application.get_env(app, :bobbin_nodes, [])
  end

  # In the order of their names, so the sidebar doesn't change between builds.
  defp apps do
    for {app, _description, _version} <- Application.loaded_applications(),
        Application.get_env(app, :bobbin_nodes) || Application.get_env(app, :bobbin_integrations) do
      app
    end
    |> Enum.sort()
  end
end
