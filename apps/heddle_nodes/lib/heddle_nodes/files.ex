defmodule HeddleNodes.Files do
  @moduledoc """
  Where the nodes written with Bobbin keep the files they pass between them, see
  `Bobbin.Files`. heddle_core is only a test dependency of this app, so the store comes
  from config, as `:files_client` (`HeddleCore.Files`).
  """

  @behaviour Bobbin.Files

  @impl true
  def store(content, meta), do: client().store(content, meta)

  @impl true
  def read(ref), do: client().read(ref)

  defp client, do: Application.fetch_env!(:heddle_nodes, :files_client)
end
