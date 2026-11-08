ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(HeddleCore.Repo, :manual)

# A flow session saves at once, and works with the database of the test that calls it.
# Only here: a server started in the test environment, as for E2E, works as in
# production. See `HeddleCore.Flows.Session`.
Application.put_env(:heddle_core, :session_flush_after, :sync)
Application.put_env(:heddle_core, :sandbox_sessions, true)
