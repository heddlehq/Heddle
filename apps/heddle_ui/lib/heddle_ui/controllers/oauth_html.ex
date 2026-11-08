defmodule HeddleUI.OAuthHTML do
  use HeddleUI, :html

  attr :client, :map, required: true
  attr :form_params, :map, required: true
  attr :workspaces, :list, required: true
  attr :current_workspace_id, :any, default: nil
  attr :flash, :map, required: true
  attr :current_scope, :map, required: true

  def new(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="min-h-[70vh] flex items-center justify-center p-4">
        <div class="w-full max-w-md bg-base-200 p-8 rounded-box border border-base-300">
          <h1 class="text-2xl font-bold text-base-content">
            {gettext("Allow %{name} to access Heddle?", name: @client.name)}
          </h1>
          <p class="mt-2 text-sm text-base-content/70">
            {gettext("%{name} on this computer is asking to sign in as %{user}.",
              name: @client.name,
              user: @current_scope.user.username
            )}
          </p>

          <p class="mt-6 text-sm font-semibold text-base-content">{gettext("It will be able to:")}</p>
          <ul class="mt-2 space-y-1 text-sm text-base-content/80">
            <li :for={scope <- @client.scopes}>{scope_label(scope)}</li>
          </ul>

          <p class="mt-6 text-xs text-base-content/60">
            {gettext(
              "Only in the workspace you pick, and no more than your role there allows. You can revoke this at any time on its API keys page."
            )}
          </p>

          <p :if={@workspaces == []} id="oauth-no-workspace" class="mt-6 text-sm text-base-content/80">
            {gettext("You aren't in a workspace yet. Ask an admin to add you to one.")}
          </p>

          <.form for={to_form(%{})} action={~p"/oauth/authorize"} class="mt-6 space-y-4">
            <input :for={{name, value} <- @form_params} type="hidden" name={name} value={value} />
            <.input
              :if={@workspaces != []}
              type="select"
              id="oauth-workspace"
              name="workspace_id"
              label={gettext("Workspace")}
              value={@current_workspace_id}
              options={
                Enum.map(@workspaces, fn {workspace, role} ->
                  {"#{workspace.name} (#{Layouts.role_label(role)})", workspace.id}
                end)
              }
            />
            <div class="flex gap-3">
              <.button
                :if={@workspaces != []}
                name="decision"
                value="allow"
                variant="primary"
                class="flex-1"
              >
                {gettext("Allow")}
              </.button>
              <.button type="submit" name="decision" value="deny" variant="ghost" class="flex-1">
                {gettext("Cancel")}
              </.button>
            </div>
          </.form>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :flash, :map, required: true
  attr :current_scope, :map, required: true

  def invalid(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="min-h-[70vh] flex items-center justify-center p-4">
        <div class="w-full max-w-md bg-base-200 p-8 rounded-box border border-base-300">
          <h1 class="text-2xl font-bold text-base-content">
            {gettext("This sign-in link isn't valid")}
          </h1>
          <p class="mt-2 text-sm text-base-content/70">
            {gettext("Start the sign-in again from the app.")}
          </p>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp scope_label("workflows:read"), do: gettext("See your workflows")
  defp scope_label("workflows:write"), do: gettext("Create and change workflows")
  defp scope_label("workflows:delete"), do: gettext("Delete workflows")
  defp scope_label("nodes:read"), do: gettext("See the available nodes")
  defp scope_label("executions:read"), do: gettext("See workflow runs")
  defp scope_label("executions:write"), do: gettext("Run workflows")
  defp scope_label(scope), do: scope
end
