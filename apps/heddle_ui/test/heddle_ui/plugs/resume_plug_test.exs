defmodule HeddleUI.Plugs.ResumePlugTest do
  use HeddleUI.ConnCase, async: true
  use Oban.Testing, repo: HeddleCore.Repo

  import HeddleCore.FlowsFixtures

  alias HeddleCore.Executions

  @worker "HeddleWorker.FlowExecutionWorker"

  defp waiting_for_call do
    paused = %{
      "wait" => %{"node_id" => "w", "call" => true},
      "context" => %{"logs" => []},
      "frames" => []
    }

    {:ok, execution} = Executions.pause(execution_fixture(), paused)
    execution
  end

  test "a link resumes the run with its query string", %{conn: conn} do
    execution = waiting_for_call()

    conn = get(conn, "/api/resume/#{execution.resume_token}?approved=yes")

    assert %{"status" => "resumed", "execution_id" => public_id} = json_response(conn, 202)
    assert public_id == execution.public_id

    assert_enqueued(
      worker: @worker,
      args: %{
        "execution_id" => execution.id,
        "wait_id" => execution.paused["wait_id"],
        "by" => "call",
        "request" => %{"body" => %{}, "query_params" => %{"approved" => "yes"}, "method" => "GET"}
      }
    )
  end

  test "a call resumes the run with its body, and only once", %{conn: conn} do
    execution = waiting_for_call()
    path = "/api/resume/#{execution.resume_token}"

    assert json_response(post(conn, path, %{"ok" => true}), 202)
    assert %{"error" => _message} = json_response(post(build_conn(), path, %{}), 409)

    assert [%{args: %{"request" => %{"body" => %{"ok" => true}}}}] =
             all_enqueued(worker: @worker)
  end

  test "an address nobody waits at is not found, and a finished run is gone", %{conn: conn} do
    assert json_response(get(conn, "/api/resume/nothing-here"), 404)

    {:ok, finished} = Executions.mark_succeeded(waiting_for_call(), %{})
    assert json_response(get(build_conn(), "/api/resume/#{finished.resume_token}"), 410)
  end
end
