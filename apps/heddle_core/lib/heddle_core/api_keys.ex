defmodule HeddleCore.ApiKeys do
  @moduledoc """
  API key management and authentication.

  A key belongs to a person and one workspace. It reaches only that workspace, with
  the role its owner has there at the time of each request, and only what its scopes
  allow: see `HeddleCore.Accounts.Scope.for_api_key/1`.
  """

  import Ecto.Query, warn: false

  alias HeddleCore.Accounts.{Scope, User}
  alias HeddleCore.ApiKeys.ApiKey
  alias HeddleCore.Repo
  alias HeddleCore.Workspaces

  @prefix_size 8
  @secret_size 32
  @max_create_attempts 5

  @agent_key_name "Claude Agent session"
  @agent_key_scopes ~w(workflows:read workflows:write nodes:read executions:read executions:write)
  @agent_key_lifetime_seconds 3600

  @doc """
  Creates a key for the caller, in the workspace they work in. Its scopes must be ones
  their role there reaches: see `ApiKey.scopes_for/1`.
  """
  def create_api_key(
        %Scope{api_key: nil, user: %User{} = user, workspace: %{id: id}} = scope,
        attrs
      ) do
    attrs = Map.new(attrs)
    scopes = attrs[:scopes] || attrs["scopes"] || []
    allowed = ApiKey.scopes_for(scope.role)

    if scope.role && Enum.all?(scopes, &(&1 in allowed)) do
      create_api_key(user, id, attrs)
    else
      {:error, :forbidden}
    end
  end

  def create_api_key(%Scope{}, _attrs), do: {:error, :forbidden}

  @doc """
  Creates a key for `user` in the workspace with `workspace_id`, which they must be in.
  """
  def create_api_key(%User{} = user, workspace_id, attrs) do
    if Workspaces.role_of(user, workspace_id) do
      attrs = attrs |> Map.new() |> Map.drop([:workspace_id, "workspace_id"])
      attrs = Map.new(attrs, fn {key, value} -> {to_atom_key(key), value} end)

      insert_api_key(user.id, Map.put(attrs, :workspace_id, workspace_id), @max_create_attempts)
    else
      {:error, :forbidden}
    end
  end

  @fields %{"name" => :name, "scopes" => :scopes, "expires_at" => :expires_at}
  defp to_atom_key(key) when is_atom(key), do: key
  defp to_atom_key(key), do: Map.get(@fields, key, key)

  defp insert_api_key(user_id, attrs, attempts_left) when attempts_left > 0 do
    prefix = generate_prefix()
    token = build_token(prefix)

    attrs =
      attrs
      |> Map.new()
      |> Map.put(:user_id, user_id)
      |> Map.put(:prefix, prefix)
      |> Map.put(:key_hash, hash_token(token))
      |> Map.put_new(:name, "API key")
      |> Map.put_new(:scopes, [])

    case %ApiKey{} |> ApiKey.create_changeset(attrs) |> Repo.insert() do
      {:ok, api_key} ->
        {:ok, %{api_key: Repo.preload(api_key, :user), token: token}}

      {:error, changeset} ->
        if prefix_collision?(changeset) do
          insert_api_key(user_id, Map.drop(attrs, [:prefix, :key_hash]), attempts_left - 1)
        else
          {:error, changeset}
        end
    end
  end

  defp insert_api_key(user_id, attrs, 0) do
    prefix = generate_prefix()
    token = build_token(prefix)

    attrs =
      attrs
      |> Map.put(:user_id, user_id)
      |> Map.put(:prefix, prefix)
      |> Map.put(:key_hash, hash_token(token))
      |> Map.put_new(:name, "API key")
      |> Map.put_new(:scopes, [])

    case %ApiKey{} |> ApiKey.create_changeset(attrs) |> Repo.insert() do
      {:ok, api_key} -> {:ok, %{api_key: Repo.preload(api_key, :user), token: token}}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def authenticate(token) when is_binary(token) do
    with {:ok, prefix} <- parse_prefix(token),
         %ApiKey{} = api_key <- get_by_prefix(prefix),
         true <- token_matches?(token, api_key),
         true <- ApiKey.active?(api_key) do
      {:ok, Repo.preload(touch_last_used(api_key), :user)}
    else
      _ -> :error
    end
  end

  def authenticate(_token), do: :error

  @doc """
  Creates the short-lived key the Claude Agent uses during one message.

  It is hidden from `list_api_keys/0,1`: it belongs to a run, not to the user.
  """
  def create_agent_key(%User{} = user, workspace_id) do
    expires_at = DateTime.add(DateTime.utc_now(:second), @agent_key_lifetime_seconds)

    create_api_key(user, workspace_id, %{
      name: @agent_key_name,
      scopes: @agent_key_scopes,
      expires_at: expires_at
    })
  end

  @doc """
  Whether a key can only run flows after a person confirms it.

  A user can name their own key the same way, which only makes it stricter.
  """
  def agent_key?(%ApiKey{name: name}), do: name == @agent_key_name

  def delete_api_key(%ApiKey{} = api_key), do: Repo.delete(api_key, allow_stale: true)

  @doc "Revokes a key: its owner can, and the admins of its workspace."
  def revoke_api_key(%Scope{} = scope, %ApiKey{} = api_key) do
    if can_revoke?(scope, api_key) do
      api_key
      |> ApiKey.revoke_changeset()
      |> Repo.update()
    else
      {:error, :forbidden}
    end
  end

  def can_revoke?(%Scope{api_key: nil, user: %User{id: user_id}} = scope, %ApiKey{} = api_key) do
    api_key.user_id == user_id or Workspaces.can?(scope, :manage, api_key.workspace_id)
  end

  def can_revoke?(_scope, _api_key), do: false

  @doc "Gets a key of the caller's workspace that they may see, or nil."
  def get_api_key(%Scope{} = scope, id) do
    with {id, ""} <- Integer.parse(to_string(id)),
         %ApiKey{} = api_key <- Repo.get(ApiKey, id),
         true <- visible?(scope, api_key) do
      Repo.preload(api_key, :user)
    else
      _other -> nil
    end
  end

  defp visible?(%Scope{user: %User{id: user_id}} = scope, %ApiKey{} = api_key) do
    api_key.user_id == user_id or Workspaces.can?(scope, :manage, api_key.workspace_id)
  end

  defp visible?(_scope, _api_key), do: false

  def list_api_keys do
    Repo.all(
      from key in ApiKey,
        where: key.name != ^@agent_key_name,
        preload: [:user],
        order_by: [desc: key.inserted_at]
    )
  end

  @doc """
  The keys of the workspace the caller works in: their own, or every one for its admins.
  """
  def list_api_keys(%Scope{user: %User{id: user_id}, workspace: %{id: workspace_id}} = scope) do
    query =
      from key in ApiKey,
        where: key.workspace_id == ^workspace_id and key.name != ^@agent_key_name,
        preload: [:user],
        order_by: [desc: key.inserted_at]

    cond do
      Workspaces.can?(scope, :manage, workspace_id) -> Repo.all(query)
      Workspaces.role(scope, workspace_id) -> Repo.all(where(query, [k], k.user_id == ^user_id))
      true -> []
    end
  end

  def list_api_keys(%Scope{}), do: []

  def hash_token(token), do: :crypto.hash(:sha256, token)

  defp get_by_prefix(prefix), do: Repo.get_by(ApiKey, prefix: prefix)

  defp parse_prefix(token) do
    case String.split(token, "_", parts: 4) do
      # Keys issued before the rename still start with "ff".
      [kind, "live", prefix, secret]
      when kind in ["hd", "ff"] and byte_size(prefix) == @prefix_size and byte_size(secret) > 0 ->
        {:ok, prefix}

      _ ->
        :error
    end
  end

  defp build_token(prefix) do
    secret = @secret_size |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
    "hd_live_#{prefix}_#{secret}"
  end

  defp generate_prefix do
    @prefix_size
    |> :crypto.strong_rand_bytes()
    |> Base.encode16(case: :lower)
    |> binary_part(0, 8)
  end

  defp prefix_collision?(changeset) do
    Keyword.has_key?(changeset.errors, :prefix)
  end

  defp token_matches?(token, %ApiKey{key_hash: key_hash}) do
    token_hash = hash_token(token)
    byte_size(token_hash) == byte_size(key_hash) and :crypto.hash_equals(token_hash, key_hash)
  end

  defp touch_last_used(%ApiKey{} = api_key) do
    now = DateTime.utc_now()

    should_update? =
      case api_key.last_used_at do
        nil -> true
        last_used -> DateTime.diff(now, last_used, :second) > 60
      end

    if should_update?, do: persist_last_used(api_key)

    %{api_key | last_used_at: if(should_update?, do: now, else: api_key.last_used_at)}
  end

  defp persist_last_used(%ApiKey{} = api_key) do
    task = fn ->
      case api_key |> ApiKey.touch_changeset() |> Repo.update() do
        {:ok, _api_key} -> :ok
        _ -> :error
      end
    end

    if Application.get_env(:heddle_core, :async_api_key_touch?, true) do
      Task.Supervisor.start_child(HeddleCore.TaskSupervisor, task)
    else
      task.()
    end
  end
end
