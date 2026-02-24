defmodule FusionFlowWeb.UserLive.InviteRegister do
  use FusionFlowWeb, :live_view

  alias FusionFlow.Accounts

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    if socket.assigns[:current_scope] && socket.assigns.current_scope.user do
      {:ok,
       socket
       |> put_flash(:info, gettext("You are already logged in."))
       |> redirect(to: ~p"/")}
    else
      case Accounts.get_invite_by_token(token) do
        :error ->
          {:ok,
           socket
           |> put_flash(:error, gettext("This invite link is invalid or has expired."))
           |> redirect(to: ~p"/users/log-in")}

        {:ok, _inviter, _token_struct} ->
          form =
            %FusionFlow.Accounts.User{}
            |> FusionFlow.Accounts.User.registration_changeset(%{})
            |> FusionFlow.Accounts.User.password_changeset(%{})
            |> to_form(as: "user")

          {:ok,
           socket
           |> assign(:page_title, gettext("Create your account"))
           |> assign(:token, token)
           |> assign(:form, form)}
      end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-[80vh] flex flex-col items-center justify-center p-4">
      <div class="w-full max-w-md bg-white dark:bg-slate-800 p-8 rounded-3xl shadow-2xl border border-gray-100 dark:border-slate-700/50">
        <div class="text-center mb-8">
          <h1 class="text-3xl font-extrabold text-gray-900 dark:text-white tracking-tight">
            {gettext("Create your account")}
          </h1>

          <p class="mt-2 text-sm text-gray-500 dark:text-gray-400">
            {gettext("You were invited to join FusionFlow. Fill in your details below.")}
          </p>
        </div>

        <.form
          for={@form}
          id="invite-register-form"
          phx-submit="save"
          class="space-y-5"
        >
          <.input
            field={@form[:username]}
            type="text"
            label={gettext("Username")}
            placeholder={gettext("Enter your username")}
            required
            phx-mounted={JS.focus()}
          />
          <.input
            field={@form[:email]}
            type="email"
            label={gettext("Email")}
            placeholder={gettext("Enter your email")}
            required
          />
          <.input
            field={@form[:password]}
            type="password"
            label={gettext("Password")}
            placeholder="••••••••"
            required
          />
          <.input
            field={@form[:password_confirmation]}
            type="password"
            label={gettext("Confirm password")}
            placeholder="••••••••"
            required
          />
          <div class="pt-2">
            <.button
              type="submit"
              variant="primary"
              class="w-full py-4 text-base font-bold shadow-lg shadow-indigo-500/25 transition-all hover:shadow-indigo-500/40 active:scale-[0.98]"
            >
              {gettext("Create account")}
            </.button>
          </div>
        </.form>

        <p class="mt-6 text-center text-sm text-gray-500 dark:text-gray-400">
          <.link href={~p"/users/log-in"} class="text-primary hover:underline">
            {gettext("Already have an account? Log in")}
          </.link>
        </p>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("save", %{"user" => user_params}, socket) do
    token = socket.assigns.token

    case Accounts.register_user_from_invite(user_params, token) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Account created successfully. You can now log in."))
         |> redirect(to: ~p"/users/log-in")}

      {:error, %Ecto.Changeset{} = changeset} ->
        # Rebuild changeset from params so all fields (including password) persist when showing errors
        form_changeset =
          %FusionFlow.Accounts.User{}
          |> FusionFlow.Accounts.User.registration_changeset(user_params)
          |> FusionFlow.Accounts.User.password_changeset(user_params)
          |> Ecto.Changeset.merge(changeset)

        form = to_form(form_changeset, as: "user")

        {:noreply,
         socket
         |> assign(:form, form)}
    end
  end
end
