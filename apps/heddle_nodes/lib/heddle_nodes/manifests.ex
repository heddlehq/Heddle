defmodule HeddleNodes.Manifests do
  @moduledoc """
  The integrations written as manifests (see `Bobbin.Integration`): the ones a
  workspace downloaded from the catalog (`HeddleNodes.Community`), and the ones packages
  carry (`HeddleNodes.Packages`). `Bobbin.Integration.Runtime` runs their nodes.

  Each trigger becomes a node a flow starts from. A polling trigger is called by
  `HeddleWorker.PollWorker` every few minutes, see `poll/3`, which starts the flow
  once for each new item. A webhook trigger is called by the service, at the address
  `HeddleWorker.HookWorker` registers when the flow is published (see
  `HeddleCore.Integrations.Hooks`). Either way the node passes the item on as
  `result`.
  """

  alias Bobbin.Integration.Runtime

  @doc "A manifest's credential, in the form `HeddleCore.Credentials` takes."
  def credential_kind(credential) do
    kind = %{
      id: credential.kind,
      label: credential.label,
      fields:
        Enum.map(credential.fields, fn field ->
          %{name: field.name, label: field.label, secret: field.secret, required: field.required}
        end)
    }

    case credential.auth do
      %{"type" => "oauth2"} = auth ->
        Map.merge(kind, %{
          fields: oauth_fields(),
          oauth2: %{
            authorize_url: auth["authorize_url"],
            token_url: auth["token_url"],
            scopes: auth["scopes"] || [],
            token_auth: auth["token_auth"],
            token_body: auth["token_body"],
            authorize_params: auth["authorize_params"] || %{}
          }
        })

      _other ->
        kind
    end
  end

  # What a credential that connects through OAuth 2.0 keeps, see
  # HeddleCore.Credentials.OAuth.
  defp oauth_fields do
    [
      %{name: "access_token", label: "Access token", secret: true, required: true},
      %{name: "refresh_token", label: "Refresh token", secret: true, required: false},
      %{name: "expires_at", label: "Expires at", secret: false, required: false}
    ]
  end

  @doc "Every manifest the instance runs: the packages' and the downloaded ones."
  def all, do: HeddleNodes.Packages.manifests() ++ HeddleNodes.Community.manifests()

  @doc "The credential kinds the manifests declare."
  def all_credential_kinds do
    for(%{credential: %{} = credential} <- all(), do: credential_kind(credential))
    |> Enum.uniq_by(& &1.id)
  end

  defdelegate run(manifest, action_name, context), to: Runtime
  defdelegate poll(manifest, trigger_name, context), to: Runtime
  defdelegate trigger(manifest, trigger_name, context), to: Runtime
  defdelegate options(manifest, step_name, field_name, context), to: Runtime
  defdelegate register_webhook(manifest, trigger_name, context, webhook), to: Runtime
  defdelegate unregister_webhook(manifest, trigger_name, context, webhook), to: Runtime
  defdelegate receive_webhook(manifest, trigger_name, context, event, webhook), to: Runtime

  @doc """
  The polling trigger nodes of every manifest:
  `[%{type: node_name, manifest: manifest, trigger: trigger}]`.
  """
  def poll_triggers, do: Enum.reject(triggers(), & &1.trigger.webhook)

  @doc "The webhook trigger nodes of every manifest, like `poll_triggers/0`."
  def webhook_triggers, do: Enum.filter(triggers(), & &1.trigger.webhook)

  @doc "The webhook trigger whose node is of `type`, or nil."
  def webhook_trigger(type), do: Enum.find(webhook_triggers(), &(&1.type == type))

  @doc """
  The manifest and the action or trigger of a node of `type`, or nil:
  `%{manifest: manifest, step: step}`.
  """
  def step(type) do
    Enum.find_value(all(), fn manifest ->
      Enum.find_value(manifest.triggers ++ manifest.actions, fn step ->
        if "#{manifest.name}: #{step.name}" == type, do: %{manifest: manifest, step: step}
      end)
    end)
  end

  defp triggers do
    for manifest <- all(), trigger <- manifest.triggers do
      %{type: "#{manifest.name}: #{trigger.name}", manifest: manifest, trigger: trigger}
    end
  end
end
