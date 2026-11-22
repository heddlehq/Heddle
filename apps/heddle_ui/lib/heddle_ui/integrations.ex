defmodule HeddleUI.Integrations do
  @moduledoc """
  The integrations the caller's workspace has, joining what it installed
  (`HeddleCore.Integrations`) with what each integration holds
  (`HeddleNodes.Integrations`).
  """

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
end
