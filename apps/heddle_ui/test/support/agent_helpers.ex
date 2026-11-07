defmodule HeddleUI.AgentHelpers do
  @moduledoc """
  Keeps the conversations of one test from reaching the next.
  """

  alias HeddleUI.Agent
  alias HeddleUI.FakeHarnessModel

  def stop_all do
    for {_id, pid, _type, _modules} <- DynamicSupervisor.which_children(Agent.supervisor()) do
      DynamicSupervisor.terminate_child(Agent.supervisor(), pid)
    end

    for pid <- Task.Supervisor.children(Agent.task_supervisor()) do
      Task.Supervisor.terminate_child(Agent.task_supervisor(), pid)
    end
  end

  @doc "Waits for the model to take all of its script, the last step being one that hangs."
  def wait_for_script(attempts \\ 400) do
    if FakeHarnessModel.remaining() != [] and attempts > 0 do
      Process.sleep(5)
      wait_for_script(attempts - 1)
    end
  end
end
