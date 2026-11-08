defmodule HeddleCore.Workspaces.Role do
  @moduledoc """
  What a role lets a person do in a workspace.

  Each role holds everything the one below it does, so there are four actions to check
  and nothing to combine:

    * `viewer` can `:view` flows, runs, the names of credentials and the members.
    * `operator` can also `:run` flows, without changing them.
    * `editor` can also `:edit`: create, change and delete flows and credentials, and
      use the agent and the Terminal, which change flows too.
    * `admin` can also `:manage` the workspace: its name, members and invites, and
      every API key in it.

  System admins act as `admin` in every workspace. Only they create and delete
  workspaces, and change what is shared with all of them.
  """

  @roles ["admin", "editor", "operator", "viewer"]
  @rank %{"viewer" => 0, "operator" => 1, "editor" => 2, "admin" => 3}
  @needs %{view: "viewer", run: "operator", edit: "editor", manage: "admin"}

  @type t :: String.t()
  @type action :: :view | :run | :edit | :manage

  @doc "Every role, from the one that can do the most."
  def all, do: @roles

  def valid?(role), do: role in @roles

  @doc "Whether `role` may do `action`."
  @spec allows?(t() | nil, action()) :: boolean()
  def allows?(role, action) when is_map_key(@rank, role) and is_map_key(@needs, action) do
    @rank[role] >= @rank[@needs[action]]
  end

  def allows?(_role, _action), do: false

  @doc "The role that can do the least of the two."
  def lowest(a, b) when is_map_key(@rank, a) and is_map_key(@rank, b) do
    if @rank[a] <= @rank[b], do: a, else: b
  end

  def lowest(_a, _b), do: nil

  @doc "Whether `role` reaches at least `other`."
  def at_least?(role, other) when is_map_key(@rank, role) and is_map_key(@rank, other) do
    @rank[role] >= @rank[other]
  end

  def at_least?(_role, _other), do: false
end
