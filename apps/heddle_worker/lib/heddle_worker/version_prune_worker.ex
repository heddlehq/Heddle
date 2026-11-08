defmodule HeddleWorker.VersionPruneWorker do
  @moduledoc """
  Runs once a day and deletes the versions of flows that nothing needs anymore: old
  checkpoints and run versions that aren't published, the newest of their flow, or what
  a run ran. See `HeddleCore.Flows.Versions.prune/1`.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    count = HeddleCore.Flows.Versions.prune()
    if count > 0, do: Logger.info("Deleted #{count} old versions of flows")
    :ok
  end
end
