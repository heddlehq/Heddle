defmodule HeddleUI.CredentialLive.Index do
  use HeddleUI, :live_view

  on_mount {HeddleUI.UserAuth, :require_system_admin}

  alias HeddleCore.Credentials
  alias HeddleCore.Credentials.Credential

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Credentials"))
     |> assign(:kinds, Credentials.kinds())
     |> assign_form(%Credential{kind: "slack"}, %{})
     |> stream_credentials()}
  end

  @impl true
  def handle_event("change", %{"credential" => params}, socket) do
    credential = %{socket.assigns.credential | kind: params["kind"]}

    {:noreply, assign_form(socket, credential, params)}
  end

  def handle_event("save", %{"credential" => params}, socket) do
    case save(socket.assigns.credential, params) do
      {:ok, _credential} ->
        {:noreply,
         socket
         |> assign_form(%Credential{kind: "slack"}, %{})
         |> stream_credentials()
         |> put_flash(:info, gettext("Credential saved."))}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:form, to_form(changeset, as: :credential, action: :validate))
         |> assign(:values, params["values"] || %{})}
    end
  end

  def handle_event("edit", %{"id" => id}, socket) do
    credential = Credentials.get_credential!(id)

    {:noreply,
     assign_form(socket, credential, %{
       "name" => credential.name,
       "kind" => credential.kind,
       "values" => Credentials.public_values(credential)
     })}
  end

  def handle_event("cancel", _params, socket) do
    {:noreply, assign_form(socket, %Credential{kind: "slack"}, %{})}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    credential = Credentials.get_credential!(id)
    {:ok, _credential} = Credentials.delete_credential(credential)

    {:noreply,
     socket
     |> stream_delete(:credentials, credential)
     |> assign(:empty?, Credentials.list_credentials() == [])
     |> put_flash(:info, gettext("Credential deleted."))}
  end

  defp save(%Credential{id: nil}, params), do: Credentials.create_credential(params)
  defp save(credential, params), do: Credentials.update_credential(credential, params)

  defp assign_form(socket, credential, params) do
    changeset = Credentials.change_credential(credential, Map.take(params, ["name", "kind"]))

    socket
    |> assign(:credential, credential)
    |> assign(:form, to_form(changeset, as: :credential))
    |> assign(:values, params["values"] || %{})
  end

  defp stream_credentials(socket) do
    credentials = Credentials.list_credentials()

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

  defp secret_placeholder(%Credential{id: nil}), do: ""
  defp secret_placeholder(_credential), do: gettext("Leave blank to keep the current value")

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 md:p-8 w-full max-w-5xl mx-auto">
      <h1 class="text-2xl font-semibold text-gray-900 dark:text-white">{gettext("Credentials")}</h1>
      <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
        {gettext(
          "Secrets your flows use to reach other services. They are stored encrypted and never shown again."
        )}
      </p>

      <div class="mt-8 grid gap-8 md:grid-cols-2">
        <.form
          for={@form}
          id="credential-form"
          phx-change="change"
          phx-submit="save"
          class="space-y-4 rounded-lg border border-gray-200 bg-white p-6 dark:border-slate-800 dark:bg-slate-900"
        >
          <.input field={@form[:name]} type="text" label={gettext("Name")} required />
          <.input
            field={@form[:kind]}
            type="select"
            label={gettext("Service")}
            options={Enum.map(@kinds, &{&1.label, &1.id})}
            disabled={!is_nil(@credential.id)}
          />
          <input :if={@credential.id} type="hidden" name="credential[kind]" value={@credential.kind} />

          <%= for field <- fields(@credential.kind) do %>
            <.input
              id={"credential-value-#{field.name}"}
              name={"credential[values][#{field.name}]"}
              type={if(field[:secret], do: "password", else: "text")}
              label={field.label}
              value={if(field[:secret], do: "", else: @values[field.name] || field[:default])}
              placeholder={if(field[:secret], do: secret_placeholder(@credential))}
              autocomplete="off"
            />
          <% end %>

          <div class="flex gap-2 pt-2">
            <.button id="credential-save" type="submit" variant="primary">
              {if(@credential.id, do: gettext("Save changes"), else: gettext("Add credential"))}
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

        <div>
          <p :if={@empty?} id="credentials-empty" class="text-sm text-gray-500 dark:text-gray-400">
            {gettext("No credentials yet.")}
          </p>

          <div id="credentials" phx-update="stream" class="space-y-2">
            <div
              :for={{id, credential} <- @streams.credentials}
              id={id}
              class="flex items-center justify-between rounded-lg border border-gray-200 bg-white px-4 py-3 dark:border-slate-800 dark:bg-slate-900"
            >
              <div class="min-w-0">
                <p class="truncate text-sm font-medium text-gray-900 dark:text-white">
                  {credential.name}
                </p>
                <p class="text-xs text-gray-500 dark:text-gray-400">
                  {kind_label(credential.kind)}
                </p>
              </div>
              <div class="flex shrink-0 gap-1">
                <.button
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
