defmodule HeddleNodes.BobbinHost do
  @moduledoc """
  What Heddle gives the nodes written with Bobbin, see `Bobbin.Host`: the credentials
  of each workspace.

  heddle_core is only a test dependency of this app, so the credential store comes
  from config, as `:credentials_client`.
  """

  @behaviour Bobbin.Host

  @impl true
  def credential(workspace_id, name, kind, opts) do
    client = Application.fetch_env!(:heddle_nodes, :credentials_client)
    args = [workspace_id, name, kind]

    if opts == [], do: apply(client, :fetch, args), else: apply(client, :fetch, args ++ [opts])
  end
end
