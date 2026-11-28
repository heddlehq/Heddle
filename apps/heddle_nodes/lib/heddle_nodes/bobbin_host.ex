defmodule HeddleNodes.BobbinHost do
  @moduledoc """
  What Heddle gives the nodes written with Bobbin, see `Bobbin.Host`: the credentials
  of each workspace, and a store for what a package keeps between runs.

  heddle_core is only a test dependency of this app, so they come from config, as
  `:credentials_client` and `:store_client` (`HeddleCore.PackageStore`).
  """

  @behaviour Bobbin.Host

  @impl true
  def credential(workspace_id, name, kind, opts) do
    client = Application.fetch_env!(:heddle_nodes, :credentials_client)
    args = [workspace_id, name, kind]

    if opts == [], do: apply(client, :fetch, args), else: apply(client, :fetch, args ++ [opts])
  end

  @impl true
  def store_get(workspace_id, namespace, key, opts),
    do: store().get(workspace_id, namespace, key, opts)

  @impl true
  def store_put(workspace_id, namespace, key, value, opts),
    do: store().put(workspace_id, namespace, key, value, opts)

  @impl true
  def store_delete(workspace_id, namespace, key, opts),
    do: store().delete(workspace_id, namespace, key, opts)

  @impl true
  def store_list(workspace_id, namespace, prefix, opts),
    do: store().list(workspace_id, namespace, prefix, opts)

  defp store, do: Application.fetch_env!(:heddle_nodes, :store_client)
end
