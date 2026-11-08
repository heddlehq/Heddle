defmodule HeddleUI.WorkspaceHook do
  @moduledoc """
  Gives every LiveView the workspaces for the switcher in the sidebar, and handles a
  switch from any page.

  Switching navigates again, so the page mounts with the new workspace: nothing it had
  loaded from the old one stays on screen.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView

  alias HeddleCore.Accounts.Scope
  alias HeddleCore.Workspaces

  def on_mount(:default, _params, _session, socket) do
    case socket.assigns[:current_scope] do
      %Scope{user: %{}} = scope ->
        {:cont,
         socket
         |> assign(:workspaces, Workspaces.list_workspaces(scope))
         |> attach_hook(:switch_workspace, :handle_event, &handle_event/3)}

      _other ->
        {:cont, assign(socket, :workspaces, [])}
    end
  end

  defp handle_event("switch_workspace", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope

    with %{} = workspace <- Workspaces.get_workspace(id),
         {:ok, _scope} <- Workspaces.switch_workspace(scope, workspace) do
      {:halt, push_navigate(socket, to: landing(socket.assigns[:current_path]))}
    else
      _other ->
        {:halt,
         put_flash(
           socket,
           :error,
           Gettext.gettext(HeddleUI.Gettext, "You can't open that workspace.")
         )}
    end
  end

  defp handle_event(_event, _params, socket), do: {:cont, socket}

  # A flow or a run belongs to the old workspace: go back to its list.
  defp landing("/flows/" <> _rest), do: "/flows"
  defp landing("/executions/" <> _rest), do: "/executions"
  defp landing(path) when is_binary(path), do: path
  defp landing(_path), do: "/"
end
