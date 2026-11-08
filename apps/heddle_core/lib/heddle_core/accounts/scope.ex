defmodule HeddleCore.Accounts.Scope do
  @moduledoc """
  Who is calling, and from which workspace.

  Every context function that reads or changes something a person owns takes a scope
  first. `workspace` is the one the caller works in, and `role` is theirs in it: see
  `HeddleCore.Workspaces.Role`. A caller with no workspace sees nothing.

  For a user, the workspace is the one they last chose. For an API key, it is the
  key's own, and the role is the one its owner has there now: a key stops working
  when its owner leaves, and does no more than they can. What each request may do is
  also limited by the key's scopes, which the API and the MCP check.
  """

  alias HeddleCore.Accounts.User
  alias HeddleCore.ApiKeys.ApiKey
  alias HeddleCore.Workspaces
  alias HeddleCore.Workspaces.Workspace

  defstruct user: nil, api_key: nil, api_scopes: [], workspace: nil, role: nil

  @type t :: %__MODULE__{
          user: %User{} | nil,
          api_key: %ApiKey{} | nil,
          api_scopes: [String.t()],
          workspace: %Workspace{} | nil,
          role: String.t() | nil
        }

  @doc """
  Creates a scope for the given user, in the workspace they last chose.

  Returns nil if no user is given.
  """
  def for_user(%User{} = user) do
    case Workspaces.current(user) do
      {workspace, role} -> %__MODULE__{user: user, workspace: workspace, role: role}
      nil -> %__MODULE__{user: user}
    end
  end

  def for_user(nil), do: nil

  @doc "Creates a scope for a request made with `api_key`."
  def for_api_key(%ApiKey{user: %User{} = user, scopes: scopes} = api_key) do
    workspace = Workspaces.get_workspace(api_key.workspace_id)

    %__MODULE__{
      user: user,
      api_key: api_key,
      api_scopes: scopes || [],
      workspace: workspace,
      role: workspace && Workspaces.role_of(user, workspace.id)
    }
  end

  @doc "The same caller, working in `workspace`."
  def in_workspace(%__MODULE__{api_key: nil, user: %User{} = user} = scope, %Workspace{} = ws) do
    %{scope | workspace: ws, role: Workspaces.role_of(user, ws.id)}
  end

  def in_workspace(%__MODULE__{} = scope, _workspace), do: scope

  @doc "Whether the caller is a system admin, who manages the whole instance."
  def system_admin?(%__MODULE__{user: user}), do: User.system_admin?(user)
  def system_admin?(_scope), do: false
end
