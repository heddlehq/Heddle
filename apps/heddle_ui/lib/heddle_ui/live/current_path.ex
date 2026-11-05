defmodule HeddleUI.CurrentPath do
  @moduledoc """
  Assigns `:current_path` on every LiveView, so the layout can highlight the page
  in the sidebar. It follows `push_patch` too, because it runs on `handle_params`.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4]

  def on_mount(:default, _params, _session, socket) do
    {:cont, attach_hook(socket, :current_path, :handle_params, &assign_path/3)}
  end

  defp assign_path(_params, uri, socket) do
    {:cont, assign(socket, :current_path, URI.parse(uri).path)}
  end
end
