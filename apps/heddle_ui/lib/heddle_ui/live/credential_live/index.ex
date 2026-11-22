defmodule HeddleUI.CredentialLive.Index do
  use HeddleUI, :live_view

  on_mount {HeddleUI.UserAuth, {:require_workspace, :view}}

  alias HeddleCore.Accounts.Scope
  alias HeddleCore.Credentials
  alias HeddleCore.Credentials.Credential
  alias HeddleCore.Credentials.OAuth
  alias HeddleCore.Workspaces

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    {:ok,
     socket
     |> assign(:page_title, gettext("Credentials"))
     |> assign(:can_edit, Workspaces.can?(scope, :edit))
     |> assign(:system_admin, Scope.system_admin?(scope))
     |> assign(:kinds, Credentials.kinds())
     |> assign_form(%Credential{kind: "slack"}, %{})
     |> stream_credentials()}
  end

  @impl true
  def handle_event("change", %{"credential" => params}, socket) do
    credential = %{socket.assigns.credential | kind: params["kind"]}

    {:noreply, assign_form(socket, credential, params)}
  end

  def handle_event("save", %{"credential" => params}, socket) when socket.assigns.oauth do
    query =
      URI.encode_query(%{
        "kind" => socket.assigns.credential.kind,
        "name" => params["name"] || "",
        "shared" => params["shared"] || "false"
      })

    {:noreply, redirect(socket, to: "/integrations/oauth/start?" <> query)}
  end

  def handle_event("save", %{"credential" => params}, socket) do
    case save(socket.assigns.current_scope, socket.assigns.credential, params) do
      {:ok, _credential} ->
        {:noreply,
         socket
         |> assign_form(%Credential{kind: "slack"}, %{})
         |> stream_credentials()
         |> put_flash(:info, gettext("Credential saved."))}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, forbidden_message())}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:form, to_form(changeset, as: :credential, action: :validate))
         |> assign(:values, params["values"] || %{})}
    end
  end

  def handle_event("save_app", %{"app" => app}, socket) do
    kind = socket.assigns.credential.kind

    case OAuth.put_app(socket.assigns.current_scope, kind, app["client_id"], app["client_secret"]) do
      {:ok, _app} ->
        {:noreply,
         socket
         |> assign(:oauth_app?, true)
         |> put_flash(:info, gettext("App saved. Accounts of this service can connect now."))}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, gettext("Only system admins register apps."))}

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  def handle_event("edit", %{"id" => id}, socket) do
    case changeable(socket, id) do
      nil ->
        {:noreply, put_flash(socket, :error, forbidden_message())}

      credential ->
        {:noreply,
         assign_form(socket, credential, %{
           "name" => credential.name,
           "kind" => credential.kind,
           "values" => Credentials.public_values(credential)
         })}
    end
  end

  def handle_event("cancel", _params, socket) do
    {:noreply, assign_form(socket, %Credential{kind: "slack"}, %{})}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope

    with %Credential{} = credential <- changeable(socket, id),
         {:ok, _credential} <- Credentials.delete_credential(scope, credential) do
      {:noreply,
       socket
       |> stream_delete(:credentials, credential)
       |> assign(:empty?, Credentials.list_credentials(scope) == [])
       |> put_flash(:info, gettext("Credential deleted."))}
    else
      _other -> {:noreply, put_flash(socket, :error, forbidden_message())}
    end
  end

  defp changeable(socket, id) do
    scope = socket.assigns.current_scope

    with %Credential{} = credential <- Credentials.get_credential(scope, id),
         true <- Credentials.can_change?(scope, credential) do
      credential
    else
      _other -> nil
    end
  end

  defp forbidden_message, do: gettext("Your role in this workspace can't change this credential.")

  defp save(scope, %Credential{id: nil}, params), do: Credentials.create_credential(scope, params)

  defp save(scope, credential, params),
    do: Credentials.update_credential(scope, credential, params)

  defp assign_form(socket, credential, params) do
    changeset = Credentials.change_credential(credential, Map.take(params, ["name", "kind"]))

    oauth = match?(%{oauth2: _}, Credentials.kind(credential.kind))

    socket
    |> assign(:credential, credential)
    |> assign(:oauth, oauth)
    |> assign(:oauth_app?, oauth and OAuth.app?(credential.kind))
    |> assign(:shared, params["shared"] == "true" or not socket.assigns.can_edit)
    |> assign(:form, to_form(changeset, as: :credential))
    |> assign(:values, params["values"] || %{})
  end

  defp stream_credentials(socket) do
    credentials = Credentials.list_credentials(socket.assigns.current_scope)

    socket
    |> assign(:empty?, credentials == [])
    |> stream(:credentials, credentials, reset: true)
  end

  defp kind_label(id) do
    case Credentials.kind(id) do
      nil -> id
      kind -> kind.label
    end
  end

  defp fields(kind_id) do
    case Credentials.kind(kind_id) do
      nil -> []
      kind -> kind.fields
    end
  end

  defp oauth_kind?(kind), do: match?(%{oauth2: _}, Credentials.kind(kind))

  defp secret_placeholder(%Credential{id: nil}), do: ""
  defp secret_placeholder(_credential), do: gettext("Leave blank to keep the current value")

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 md:p-8 w-full max-w-7xl mx-auto space-y-8">
      <div>
        <h1 class="text-2xl font-bold text-gray-900 dark:text-white">{gettext("Credentials")}</h1>
        <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
          {gettext(
            "Secrets the flows of this workspace use to reach other services. They are stored encrypted and never shown again."
          )}
        </p>
      </div>

      <div class="grid items-start gap-8 md:grid-cols-2">
        <div
          :if={not @can_edit and not @system_admin}
          id="credentials-read-only"
          class="rounded-xl border border-gray-200 bg-white p-6 text-sm text-gray-600 dark:border-slate-800 dark:bg-slate-900 dark:text-gray-300"
        >
          <.icon name="hero-eye" class="size-5 text-gray-400" />
          <p class="mt-2">
            {gettext("Your role lets you see which credentials exist. Editors add and change them.")}
          </p>
        </div>
        <.form
          :if={@can_edit or @system_admin}
          for={@form}
          id="credential-form"
          phx-change="change"
          phx-submit="save"
          class="space-y-4 rounded-xl border border-gray-200 bg-white p-6 shadow-sm dark:border-slate-800 dark:bg-slate-900"
        >
          <h2 class="text-lg font-semibold text-gray-900 dark:text-white">
            {if(@credential.id, do: gettext("Edit credential"), else: gettext("New credential"))}
          </h2>

          <.input field={@form[:name]} type="text" label={gettext("Name")} required />
          <.input
            field={@form[:kind]}
            type="select"
            label={gettext("Service")}
            options={Enum.map(@kinds, &{&1.label, &1.id})}
            disabled={!is_nil(@credential.id)}
          />
          <input :if={@credential.id} type="hidden" name="credential[kind]" value={@credential.kind} />

          <div :if={@oauth} id="credential-oauth" class="space-y-3">
            <p :if={@oauth_app?} class="text-sm text-gray-500 dark:text-gray-400">
              {gettext(
                "Connecting opens the service, where you allow Heddle in. It keeps the connection and renews it."
              )}
            </p>
            <div
              :if={not @oauth_app?}
              id="credential-oauth-no-app"
              class="rounded-lg border border-amber-300/60 bg-amber-50 p-3 text-sm text-amber-800 dark:border-amber-500/30 dark:bg-amber-500/10 dark:text-amber-200"
            >
              <%= if @system_admin do %>
                {gettext(
                  "Register an app with this service first, below, with this address to send people back to:"
                )}
                <code class="mt-1 block break-all rounded bg-white/70 px-2 py-1 text-xs dark:bg-slate-900/60">
                  {HeddleUI.CredentialOAuthController.callback_url()}
                </code>
              <% else %>
                {gettext(
                  "A system admin has to register an app with this service before accounts can connect."
                )}
              <% end %>
            </div>
          </div>

          <%= for field <- if(@oauth, do: [], else: fields(@credential.kind)) do %>
            <%= if field[:options] do %>
              <.input
                id={"credential-value-#{field.name}"}
                name={"credential[values][#{field.name}]"}
                type="select"
                label={field.label}
                value={@values[field.name] || field[:default]}
                options={Enum.map(field.options, &{&1.label, &1.value})}
              />
            <% else %>
              <.input
                id={"credential-value-#{field.name}"}
                name={"credential[values][#{field.name}]"}
                type={if(field[:secret], do: "password", else: "text")}
                label={field.label}
                value={if(field[:secret], do: "", else: @values[field.name] || field[:default])}
                placeholder={if(field[:secret], do: secret_placeholder(@credential))}
                list={field[:suggestions] && "credential-suggestions-#{field.name}"}
                autocomplete="off"
              />
              <datalist :if={field[:suggestions]} id={"credential-suggestions-#{field.name}"}>
                <option :for={suggestion <- field.suggestions} value={suggestion} />
              </datalist>
            <% end %>
          <% end %>

          <label
            :if={@system_admin and is_nil(@credential.id)}
            for="credential-shared"
            class="flex items-start gap-3 rounded-lg border border-gray-200 p-3 text-sm dark:border-slate-700"
          >
            <input type="hidden" name="credential[shared]" value="false" />
            <input
              id="credential-shared"
              type="checkbox"
              name="credential[shared]"
              value="true"
              checked={@shared}
              disabled={not @can_edit}
              class="mt-0.5 size-4 rounded border-gray-300 text-primary focus:ring-primary dark:border-slate-600 dark:bg-slate-800"
            />
            <span>
              <span class="block font-medium text-gray-900 dark:text-white">
                {gettext("Share with every workspace")}
              </span>
              <span class="block text-gray-500 dark:text-gray-400">
                {gettext(
                  "Every workspace can use it, and only system admins can change it. The AI defaults use shared credentials."
                )}
              </span>
            </span>
          </label>

          <div class="flex gap-2 pt-2">
            <.button
              id="credential-save"
              type="submit"
              variant="primary"
              disabled={@oauth and not @oauth_app?}
            >
              <%= cond do %>
                <% @oauth -> %>
                  <.icon name="hero-link" class="size-4" /> {gettext("Connect")}
                <% @credential.id -> %>
                  {gettext("Save changes")}
                <% true -> %>
                  {gettext("Add credential")}
              <% end %>
            </.button>
            <.button
              :if={@credential.id}
              id="credential-cancel"
              type="button"
              variant="ghost"
              phx-click="cancel"
            >
              {gettext("Cancel")}
            </.button>
          </div>
        </.form>

        <.form
          :if={@oauth and @system_admin and is_nil(@credential.id)}
          for={%{}}
          as={:app}
          id="oauth-app-form"
          phx-submit="save_app"
          class="space-y-4 rounded-xl border border-gray-200 bg-white p-6 shadow-sm md:col-start-1 dark:border-slate-800 dark:bg-slate-900"
        >
          <div>
            <h2 class="text-lg font-semibold text-gray-900 dark:text-white">
              {gettext("App registered with the service")}
            </h2>
            <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
              {gettext(
                "Every workspace connects through it. Give the service this address to send people back to:"
              )}
            </p>
            <code class="mt-2 block break-all rounded bg-gray-100 px-2 py-1 text-xs dark:bg-slate-800">
              {HeddleUI.CredentialOAuthController.callback_url()}
            </code>
          </div>
          <.input
            id="oauth-app-client-id"
            name="app[client_id]"
            type="text"
            label={gettext("Client ID")}
            value=""
            required
          />
          <.input
            id="oauth-app-client-secret"
            name="app[client_secret]"
            type="password"
            label={gettext("Client secret")}
            value=""
            placeholder={if(@oauth_app?, do: gettext("Saved. Fill both in to replace it."))}
            required
          />
          <.button id="oauth-app-save" type="submit">{gettext("Save app")}</.button>
        </.form>

        <div class="md:col-start-2 md:row-start-1">
          <div
            :if={@empty?}
            id="credentials-empty"
            class="flex flex-col items-center gap-3 rounded-xl border border-dashed border-gray-300 px-6 py-12 text-center dark:border-slate-700"
          >
            <.icon name="hero-key" class="size-6 text-gray-400" />
            <p class="text-sm text-gray-500 dark:text-gray-400">{gettext("No credentials yet.")}</p>
          </div>

          <div id="credentials" phx-update="stream" class="space-y-2">
            <div
              :for={{id, credential} <- @streams.credentials}
              id={id}
              class="flex items-center justify-between rounded-xl border border-gray-200 bg-white px-4 py-3 shadow-sm dark:border-slate-800 dark:bg-slate-900"
            >
              <div class="min-w-0">
                <p class="truncate text-sm font-medium text-gray-900 dark:text-white">
                  {credential.name}
                </p>
                <p class="flex items-center gap-2 text-xs text-gray-500 dark:text-gray-400">
                  {kind_label(credential.kind)}
                  <span
                    :if={Credential.shared?(credential)}
                    class="inline-flex items-center gap-1 rounded-full bg-gray-100 px-2 py-0.5 text-[11px] font-medium text-gray-600 dark:bg-slate-800 dark:text-gray-300"
                  >
                    <.icon name="hero-globe-alt-mini" class="size-3" /> {gettext("Shared")}
                  </span>
                </p>
              </div>
              <div
                :if={Credentials.can_change?(@current_scope, credential)}
                class="flex shrink-0 gap-1"
              >
                <.button
                  :if={not oauth_kind?(credential.kind)}
                  id={"edit-#{id}"}
                  variant="ghost"
                  phx-click="edit"
                  phx-value-id={credential.id}
                  title={gettext("Edit")}
                >
                  <.icon name="hero-pencil" class="size-4" />
                </.button>
                <.button
                  id={"delete-#{id}"}
                  variant="ghost"
                  phx-click="delete"
                  phx-value-id={credential.id}
                  data-confirm={
                    gettext("Flows that use this credential will stop working. Delete it?")
                  }
                  title={gettext("Delete")}
                >
                  <.icon name="hero-trash" class="size-4" />
                </.button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
