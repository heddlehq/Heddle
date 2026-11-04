defmodule HeddleUI.ApiRouter do
  use HeddleUI, :router

  require HeddleUI.PublicAPI.V1.Routes

  HeddleUI.PublicAPI.V1.Routes.public_api_pipelines()
  HeddleUI.PublicAPI.V1.Routes.public_api_routes()

  scope "/", HeddleUI do
    pipe_through :public_api

    match :*, "/*path", ApiNotFoundController, :show
  end
end
