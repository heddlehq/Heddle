defmodule HeddleWorker.WorkerCase do
  @moduledoc """
  Test case for HeddleWorker tests.

  Sets up the Ecto SQL sandbox (via HeddleCore.DataCase) and configures
  Oban for manual testing mode so that jobs are not automatically drained.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      use Oban.Testing, repo: HeddleCore.Repo

      alias HeddleCore.Executions
      alias HeddleCore.Flows
      alias HeddleWorker.FlowExecutionWorker

      import HeddleWorker.WorkerCase
    end
  end

  setup tags do
    HeddleCore.DataCase.setup_sandbox(tags)
    :ok
  end
end
