defmodule HeddleUI.Router do
  use HeddleUI, :router

  import HeddleUI.UserAuth
  require HeddleUI.PublicAPI.V1.Routes

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {HeddleUI.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
    plug :redirect_to_setup_if_no_admin
    plug HeddleUI.Plugs.SetLocale
  end

  HeddleUI.PublicAPI.V1.Routes.public_api_pipelines()

  pipeline :redirect_if_authenticated do
    plug :redirect_if_user_is_authenticated
  end

  HeddleUI.PublicAPI.V1.Routes.public_api_routes()

  scope "/", HeddleUI do
    pipe_through :public_api

    get "/.well-known/oauth-authorization-server", OAuthMetadataController, :show
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:heddle_ui, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: HeddleUI.Telemetry
    end
  end

  ## Authentication routes

  scope "/", HeddleUI do
    pipe_through [:browser, :require_authenticated_user]

    # One live_session for the whole app: crossing sessions forces a full page reload.
    # Admin-only LiveViews declare `on_mount {HeddleUI.UserAuth, :require_system_admin}`.
    live_session :require_authenticated_user,
      on_mount: [{HeddleUI.UserAuth, :require_authenticated}] do
      live "/users/settings", UserLive.Settings, :edit
      live "/", DashboardLive.Index
      live "/users", UserLive.Index, :index
      live "/flows", FlowLive.Index
      live "/flows/new/ai", FlowLive.AICreator
      live "/flows/:id", FlowLive.Editor
      live "/executions", ExecutionLive.Index, :index
      live "/executions/:public_id", ExecutionLive.Index, :show
      live "/ai", AILive.Index
      live "/api-keys", ApiKeyLive.Index
      live "/credentials", CredentialLive.Index
      live "/workspace", WorkspaceLive.Show
      live "/workspaces", WorkspaceLive.Index
    end

    post "/users/update-password", UserSessionController, :update_password

    get "/oauth/authorize", OAuthController, :new
    post "/oauth/authorize", OAuthController, :create
  end

  scope "/", HeddleUI do
    pipe_through [:browser, :redirect_if_authenticated]

    live_session :current_user,
      on_mount: [{HeddleUI.UserAuth, :mount_current_scope}] do
      live "/setup", UserLive.Setup, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/register/:token", UserLive.Register, :new
    end

    post "/users/log-in", UserSessionController, :create
  end

  scope "/", HeddleUI do
    pipe_through [:browser]

    delete "/users/log-out", UserSessionController, :delete
  end
end
