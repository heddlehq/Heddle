defmodule HeddleCore.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias HeddleCore.Repo

  alias HeddleCore.Accounts.{Invite, Scope, User, UserNotifier, UserToken}
  alias HeddleCore.Workspaces
  alias HeddleCore.Workspaces.{Role, Workspace}

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a user by username/email and password.
  """
  def get_user_by_identifier_and_password(identifier, password)
      when is_binary(identifier) and is_binary(password) do
    user = Repo.one(from u in User, where: u.email == ^identifier or u.username == ^identifier)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  @doc "Gets a single user, or nil."
  def get_user(id), do: Repo.get(User, id)

  @doc """
  Lists all users, ordered by inserted_at descending.
  """
  def list_users do
    Repo.all(from u in User, order_by: [desc: u.inserted_at])
  end

  ## User registration

  @doc """
  Registers a user.

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> User.password_changeset(attrs)
    |> User.confirm_changeset()
    |> Repo.insert()
  end

  def register_user!(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> User.password_changeset(attrs)
    |> User.confirm_changeset()
    |> Repo.insert!()
  end

  @doc """
  Registers a new user and marks the invite as used in a single transaction.
  Ensures that if marking the invite fails, the user is not created (rollback).
  Returns `{:ok, user}` or `{:error, :invite_mark_failed}` or `{:error, changeset}`.
  """
  def register_user_with_invite(attrs, %Invite{} = invite) do
    Repo.transaction(fn ->
      with {:ok, user} <- register_user(attrs),
           {:ok, _updated_invite} <- mark_invite_used(invite),
           {:ok, user} <- join_invited_workspace(user, invite) do
        user
      else
        {:error, %Ecto.Changeset{data: %User{}} = changeset} -> Repo.rollback(changeset)
        {:error, _reason} -> Repo.rollback(:invite_mark_failed)
      end
    end)
  end

  defp join_invited_workspace(user, %Invite{workspace_id: nil}), do: {:ok, user}

  defp join_invited_workspace(user, %Invite{workspace_id: workspace_id, role: role}) do
    with {:ok, _member} <- Workspaces.join(user, workspace_id, role || "viewer") do
      user |> Ecto.Changeset.change(current_workspace_id: workspace_id) |> Repo.update()
    end
  end

  @doc """
  Returns whether at least one user is a system admin.
  Used to decide whether to show the setup page or normal login.
  """
  def has_system_admin? do
    import Ecto.Query
    Repo.exists?(from u in User, where: u.is_system_admin == true)
  end

  @doc """
  Registers the first user as system admin (used by the setup flow).
  """
  def register_system_admin(attrs) do
    Repo.transact(fn ->
      with {:ok, user} <-
             %User{}
             |> User.registration_changeset(attrs)
             |> User.password_changeset(attrs)
             |> User.confirm_changeset()
             |> User.admin_changeset(%{is_system_admin: true})
             |> Repo.insert(),
           :ok <- Workspaces.ensure_first_workspace(user) do
        {:ok, user}
      end
    end)
  end

  ## Settings

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  def sudo_mode?(user, minutes \\ -120)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  See `HeddleCore.Accounts.User.email_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    Repo.transact(fn ->
      with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
           %UserToken{sent_to: email} <- Repo.one(query),
           {:ok, user} <- Repo.update(User.email_changeset(user, %{email: email})),
           {_count, _result} <-
             Repo.delete_all(from(UserToken, where: [user_id: ^user.id, context: ^context])) do
        {:ok, user}
      else
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  @doc """
  Updates the user email directly without confirmation.
  """
  def update_user_email_directly(user, attrs) do
    user
    |> User.email_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user username.
  """
  def change_user_username(user, attrs \\ %{}, opts \\ []) do
    User.registration_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user username.
  """
  def update_user_username(user, attrs) do
    user
    |> User.registration_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates user attributes allowed only for admins (e.g. is_system_admin).

  ## Example

      iex> update_user(user, %{is_system_admin: true})
      {:ok, %User{}}
  """
  def update_user(user, attrs) do
    user
    |> User.admin_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  See `HeddleCore.Accounts.User.password_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user password.

  Returns a tuple with the updated user, as well as a list of expired tokens.

  ## Examples

      iex> update_user_password(user, %{password: ...})
      {:ok, {%User{}, [...]}}

      iex> update_user_password(user, %{password: "too short"})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_password(user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> update_user_and_delete_all_tokens()
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Gets the user with the given magic link token.
  """
  def get_user_by_magic_link_token(token) do
    with {:ok, query} <- UserToken.verify_magic_link_token_query(token),
         {user, _token} <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Logs the user in by magic link.

  There are three cases to consider:

  1. The user has already confirmed their email. They are logged in
     and the magic link is expired.

  2. The user has not confirmed their email and no password is set.
     In this case, the user gets confirmed, logged in, and all tokens -
     including session ones - are expired. In theory, no other tokens
     exist but we delete all of them for best security practices.

  3. The user has not confirmed their email but a password is set.
     This cannot happen in the default implementation but may be the
     source of security pitfalls. See the "Mixing magic link and password registration" section of
     `mix help phx.gen.auth`.
  """
  def login_user_by_magic_link(token) do
    {:ok, query} = UserToken.verify_magic_link_token_query(token)

    case Repo.one(query) do
      # Prevent session fixation attacks by disallowing magic links for unconfirmed users with password
      {%User{confirmed_at: nil, hashed_password: hash}, _token} when not is_nil(hash) ->
        raise """
        magic link log in is not allowed for unconfirmed users with a password set!

        This cannot happen with the default implementation, which indicates that you
        might have adapted the code to a different use case. Please make sure to read the
        "Mixing magic link and password registration" section of `mix help phx.gen.auth`.
        """

      {%User{confirmed_at: nil} = user, _token} ->
        user
        |> User.confirm_changeset()
        |> update_user_and_delete_all_tokens()

      {user, token} ->
        Repo.delete!(token)
        {:ok, {user, []}}

      nil ->
        {:error, :not_found}
    end
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/users/settings/confirm-email/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Delivers the magic link login instructions to the given user.
  """
  def deliver_login_instructions(%User{} = user, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)
    UserNotifier.deliver_login_instructions(user, magic_link_url_fun.(encoded_token))
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  ## Invites

  @doc """
  Returns a link-ready invite into `workspace` with `role`, made by the caller, reusing
  one they made before that is still open. Admins of the workspace can invite.
  """
  def create_invite(%Scope{user: %User{id: user_id}} = scope, %Workspace{id: ws_id}, role) do
    with :ok <- Workspaces.authorize(scope, :manage, ws_id),
         true <- Role.valid?(role) || {:error, :invalid_role} do
      now = DateTime.utc_now()

      existing =
        Repo.one(
          from i in Invite,
            where: i.invited_by_user_id == ^user_id and i.workspace_id == ^ws_id,
            where: i.role == ^role and is_nil(i.used_at) and i.expires_at > ^now,
            order_by: [desc: i.inserted_at],
            limit: 1
        )

      if existing do
        {:ok, Repo.preload(existing, [:invited_by_user, :workspace])}
      else
        %Invite{workspace_id: ws_id, role: role}
        |> Invite.changeset(%{
          token: generate_invite_token(),
          expires_at: DateTime.add(now, Invite.invite_validity_days(), :day),
          invited_by_user_id: user_id
        })
        |> Repo.insert()
        |> case do
          {:ok, invite} -> {:ok, Repo.preload(invite, [:invited_by_user, :workspace])}
          err -> err
        end
      end
    end
  end

  def create_invite(_scope, _workspace, _role), do: {:error, :forbidden}

  @doc "The invites into `workspace` nobody has used yet. Its admins can see them."
  def list_open_invites(%Scope{} = scope, %Workspace{id: ws_id}) do
    if Workspaces.can?(scope, :manage, ws_id) do
      now = DateTime.utc_now()

      Repo.all(
        from i in Invite,
          where: i.workspace_id == ^ws_id and is_nil(i.used_at) and i.expires_at > ^now,
          order_by: [desc: i.inserted_at],
          preload: [:invited_by_user]
      )
    else
      []
    end
  end

  @doc "Cancels an invite nobody used. The admins of its workspace can."
  def revoke_invite(%Scope{} = scope, %Invite{} = invite) do
    allowed? =
      if invite.workspace_id,
        do: Workspaces.can?(scope, :manage, invite.workspace_id),
        else: Scope.system_admin?(scope)

    if allowed?, do: Repo.delete(invite), else: {:error, :forbidden}
  end

  def get_invite(id) do
    case Integer.parse(to_string(id)) do
      {id, ""} -> Repo.get(Invite, id)
      _other -> nil
    end
  end

  defp generate_invite_token do
    32
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  @doc """
  Gets an invite by token. Returns nil if not found.
  """
  def get_invite_by_token(token) when is_binary(token) do
    Repo.get_by(Invite, token: token) |> Repo.preload([:invited_by_user, :workspace])
  end

  @doc """
  Marks an invite as used (sets used_at to now).
  Returns {:ok, invite} or {:error, changeset}.
  """
  def mark_invite_used(%Invite{} = invite) do
    invite
    |> Invite.changeset(%{used_at: DateTime.utc_now()})
    |> Repo.update()
  end

  @doc """
  Lists invites created by the given admin user, most recent first.
  """
  def list_invites_by_admin(%User{id: user_id}) do
    Repo.all(
      from i in Invite,
        where: i.invited_by_user_id == ^user_id,
        order_by: [desc: i.inserted_at],
        preload: [:invited_by_user, :workspace]
    )
  end

  ## Token helper

  defp update_user_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all_by(UserToken, user_id: user.id)

        Repo.delete_all(from(t in UserToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id)))

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end
end
