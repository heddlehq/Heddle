defmodule HeddleNodes.Manifests do
  @moduledoc """
  The integrations written as manifests (see `Bobbin.Integration`): the ones a
  workspace downloaded from the catalog (`HeddleNodes.Community`), and the ones packages
  carry (`HeddleNodes.Packages`). `Bobbin.Integration.Runtime` runs their nodes.

  Each trigger becomes a node a flow starts from. `HeddleWorker.PollWorker` calls it
  every few minutes, see `poll/3`, and starts the flow once for each new item, which
  the node passes on as `result`.
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

  @doc """
  The trigger nodes of every manifest:
  `[%{type: node_name, manifest: manifest, trigger: trigger}]`.
  """
  def poll_triggers do
    for manifest <- all(), trigger <- manifest.triggers do
      %{type: "#{manifest.name}: #{trigger.name}", manifest: manifest, trigger: trigger}
    end
  end
end
