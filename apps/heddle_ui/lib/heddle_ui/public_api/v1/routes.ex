defmodule HeddleUI.PublicAPI.V1.Routes do
  @moduledoc false

  defmacro public_api_pipelines do
    quote do
      pipeline :public_api do
        plug :accepts, ["json"]
      end

      # No :accepts here: MCP clients ask for text/event-stream as well as JSON.
      pipeline :mcp do
        plug HeddleUI.Plugs.ApiKeyAuth
      end

      pipeline :public_api_authenticated do
        plug HeddleUI.Plugs.ApiKeyAuth
      end

      # Editing together sends each change as it is made: it has a budget of its own.
      pipeline :public_api_live do
        plug HeddleUI.Plugs.ApiKeyAuth, rate_limit: :live
      end
    end
  end

  defmacro public_api_routes do
    quote do
      scope "/mcp" do
        pipe_through [:mcp]

        forward "/", Anubis.Server.Transport.StreamableHTTP.Plug,
          server: HeddleUI.MCP.Server,
          request_timeout: HeddleUI.MCP.Server.request_timeout()
      end

      # No :accepts here either: this one answers with text/event-stream.
      scope "/api/v1", HeddleUI.PublicAPI.V1 do
        pipe_through [:mcp]

        get "/workflows/:workflow_id/agent/events", AgentController, :events
      end

      # No :accepts here either: it answers with text/event-stream.
      scope "/api/v1", HeddleUI.PublicAPI.V1 do
        pipe_through [:public_api_live]

        get "/workflows/:workflow_id/live", LiveController, :live
      end

      scope "/api/v1", HeddleUI.PublicAPI.V1 do
        pipe_through [:public_api, :public_api_live]

        post "/workflows/:workflow_id/changes", LiveController, :changes
        post "/workflows/:workflow_id/focus", LiveController, :focus
      end

      scope "/api/v1", HeddleUI.PublicAPI.V1 do
        pipe_through [:public_api]

        get "/health", HealthController, :show
        post "/oauth/token", OAuthController, :token
      end

      scope "/api/v1", HeddleUI.PublicAPI.V1 do
        pipe_through [:public_api, :public_api_authenticated]

        get "/nodes", NodeController, :index
        get "/nodes/:type", NodeController, :show

        get "/workflows/:workflow_id/agent", AgentController, :show
        post "/workflows/:workflow_id/agent/messages", AgentController, :message
        post "/workflows/:workflow_id/agent/decision", AgentController, :decide
        post "/workflows/:workflow_id/agent/stop", AgentController, :stop
        post "/workflows/:workflow_id/agent/new", AgentController, :new_conversation

        get "/workflows/:workflow_id/executions", ExecutionController, :index
        get "/workflows/:workflow_id/executions/:public_id", ExecutionController, :show

        post "/workflows/:workflow_id/executions", ExecutionController, :create

        get "/workflows/:workflow_id/versions", VersionController, :index
        get "/workflows/:workflow_id/versions/:id", VersionController, :show
        post "/workflows/:workflow_id/publish", VersionController, :publish
        post "/workflows/:workflow_id/versions/:id/publish", VersionController, :publish_version
        post "/workflows/:workflow_id/versions/:id/restore", VersionController, :restore

        get "/workflows", WorkflowController, :index
        get "/workflows/:id", WorkflowController, :show

        post "/workflows", WorkflowController, :create
        put "/workflows/:id", WorkflowController, :update
        patch "/workflows/:id", WorkflowController, :update

        delete "/workflows/:id", WorkflowController, :delete
      end
    end
  end
end
