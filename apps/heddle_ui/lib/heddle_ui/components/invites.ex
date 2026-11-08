defmodule HeddleUI.Components.Invites do
  @moduledoc "The invite links of the Users page and of a workspace's members page."

  use HeddleUI, :html

  alias HeddleCore.Workspaces.Role

  @doc "The address someone opens to accept `invite`."
  def invite_url(invite), do: HeddleUI.Endpoint.url() <> ~p"/users/register/#{invite.token}"

  @doc "The roles to pick from, for a select."
  def role_options, do: Enum.map(Role.all(), &{HeddleUI.Layouts.role_label(&1), &1})

  attr :invite, :map, required: true
  attr :id, :string, default: "invite-url"

  @doc "A link to copy, with when it stops working."
  def invite_link(assigns) do
    ~H"""
    <div class="space-y-3">
      <div class="flex flex-wrap items-end gap-3">
        <div class="flex-1 min-w-0">
          <.input
            type="text"
            id={@id}
            name="invite_url"
            value={invite_url(@invite)}
            label={gettext("Invite URL")}
            readonly
          />
        </div>
        <.button href={invite_url(@invite)} target="_blank" variant="outline">
          <.icon name="hero-arrow-top-right-on-square" class="h-4 w-4 mr-1" />
          {gettext("Open link")}
        </.button>
      </div>
      <p class="text-xs text-gray-500 dark:text-gray-400">
        {gettext("Joins %{workspace} as %{role}. Works once, until %{date}.",
          workspace: (@invite.workspace && @invite.workspace.name) || "",
          role: HeddleUI.Layouts.role_label(@invite.role),
          date: Calendar.strftime(@invite.expires_at, "%Y-%m-%d %H:%M")
        )}
      </p>
    </div>
    """
  end
end
