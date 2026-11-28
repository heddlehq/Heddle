defmodule HeddleWorker.FilePruneWorker do
  @moduledoc """
  Runs once a day and deletes the files runs kept that are past their retention, see
  `HeddleCore.Files.prune/1`.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    count = HeddleCore.Files.prune()
    if count > 0, do: Logger.info("Deleted #{count} files of old runs")
    :ok
  end
end
