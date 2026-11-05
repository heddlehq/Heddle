alias HeddleCore.{Accounts, Flows, Webhooks}

{:ok, user} =
  Accounts.register_system_admin(%{
    email: "bench@example.com",
    username: "bench",
    password: "bench-password-1234"
  })

{:ok, flow} =
  Flows.create_flow(Accounts.Scope.for_user(user), %{
    name: "bench",
    nodes: [
      %{
        "id" => "1",
        "type" => "Webhook",
        "label" => "Webhook",
        "position" => %{"x" => 0, "y" => 0},
        "controls" => %{"method" => "POST", "path" => "/bench"}
      },
      %{
        "id" => "2",
        "type" => "HTTP Request",
        "label" => "HTTP Request",
        "position" => %{"x" => 200, "y" => 0},
        "controls" => %{
          "method" => "POST",
          "url" => "http://host.docker.internal:9099/hit",
          "headers" => "{}",
          "body" => "{}"
        }
      }
    ],
    connections: [
      %{"source" => "1", "sourceOutput" => "exec", "target" => "2", "targetInput" => "exec"}
    ]
  })

Webhooks.register_flow(flow)
IO.puts("FLOW=#{flow.id}")
