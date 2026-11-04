defmodule HeddleUI.PageController do
  use HeddleUI, :controller

  def redirect_to_flows(conn, _params) do
    redirect(conn, to: ~p"/flows")
  end
end
