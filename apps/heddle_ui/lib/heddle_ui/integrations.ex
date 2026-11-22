defmodule HeddleUI.Integrations do
  @moduledoc """
  The integrations the caller's workspace has, joining what it installed
  (`HeddleCore.Integrations`) with what each integration holds
  (`HeddleNodes.Integrations`).
  """

  use Gettext, backend: HeddleUI.Gettext

  @doc "The ids of the integrations the caller's workspace has."
  def installed_ids(scope) do
    HeddleNodes.Integrations.installed_ids(
      HeddleCore.Integrations.installed(scope),
      HeddleCore.Integrations.used_node_types(scope)
    )
  end

  @doc "Installs the integration `id` in the caller's workspace."
  def install(scope, id) do
    case HeddleNodes.Integrations.get(id) do
      nil -> {:error, :not_found}
      _integration -> HeddleCore.Integrations.install(scope, id)
    end
  end

  @doc "Removes the integration `id` from the caller's workspace, unless a flow uses it."
  def uninstall(scope, id) do
    HeddleCore.Integrations.uninstall(scope, id, HeddleNodes.Integrations.node_names(id))
  end

  @doc "The flows of the caller's workspace that use the integration `id`."
  def flows_using(scope, id) do
    HeddleCore.Integrations.flows_using(scope, HeddleNodes.Integrations.node_names(id))
  end

  @doc """
  Installs the community integration `id` from the catalog in the caller's workspace.
  The instance keeps the version it already has, if any.
  """
  def install_community(scope, id) do
    with %{} = entry <- HeddleUI.Integrations.Catalog.get(id) || {:error, :not_found},
         :ok <- check_manifest(id, entry["manifest"]),
         :ok <-
           HeddleCore.Integrations.install_community(scope, %{
             "integration" => id,
             "version" => entry["version"],
             "manifest" => entry["manifest"],
             "official" => HeddleNodes.Official.manifest?(id, entry["manifest"])
           }) do
      HeddleNodes.Community.refresh()
    end
  end

  @doc "Moves the instance to the catalog's version of the community integration `id`."
  def update_community(scope, id) do
    with %{} = entry <- HeddleUI.Integrations.Catalog.get(id) || {:error, :not_found},
         :ok <- check_manifest(id, entry["manifest"]),
         {:ok, _community} <-
           HeddleCore.Integrations.update_community(scope, %{
             "integration" => id,
             "version" => entry["version"],
             "manifest" => entry["manifest"]
           }) do
      HeddleNodes.Community.refresh()
    end
  end

  @doc """
  Checks a manifest written in the Integrations page: `{:ok, manifest}`, or
  `{:error, problems}` with what to fix, in the words of Bobbin.
  """
  def check_new(yaml) do
    with {:ok, manifest} <- HeddleNodes.Community.parse(yaml) do
      cond do
        HeddleUI.Integrations.Catalog.get(manifest.id) ||
            HeddleCore.Integrations.get_community(manifest.id) ->
          {:error, [gettext("The id %{id} is already taken: choose another.", id: manifest.id)]}

        check_community(manifest.id, yaml) != :ok ->
          {:error,
           [
             gettext(
               "%{name} takes the name of an official integration or of one of its nodes.",
               name: manifest.name
             )
           ]}

        true ->
          {:ok, manifest}
      end
    end
  end

  @doc """
  Installs a manifest written in the Integrations page in the caller's workspace,
  which only its admins may do. Like one from the catalog, the instance keeps it for
  every workspace.
  """
  def create(scope, yaml) do
    with {:ok, manifest} <- check_new(yaml),
         :ok <-
           HeddleCore.Integrations.install_community(scope, %{
             "integration" => manifest.id,
             "version" => manifest.version,
             "manifest" => yaml
           }) do
      HeddleNodes.Community.refresh()
      {:ok, manifest}
    end
  end

  # A community integration can't take the place of an official one, or of its nodes.
  # The pinned YAML of an official manifest is the official one.
  defp check_manifest(id, yaml) do
    if HeddleNodes.Official.manifest?(id, yaml) do
      :ok
    else
      check_community(id, yaml)
    end
  end

  defp check_community(id, yaml) do
    official =
      for(i <- HeddleNodes.Integrations.all(), not i.community, do: i.id) ++
        HeddleNodes.Official.ids()

    with {:ok, %{id: ^id} = manifest} <- HeddleNodes.Community.parse(yaml),
         false <- id in official,
         names = Enum.map(manifest.actions, &"#{manifest.name}: #{&1.name}"),
         false <- Enum.any?(names, &official_node?/1) do
      :ok
    else
      _invalid -> {:error, :invalid_manifest}
    end
  end

  defp official_node?(name) do
    case HeddleNodes.Nodes.get_node(name) do
      nil -> false
      node -> is_nil(node[:community])
    end
  end
end
