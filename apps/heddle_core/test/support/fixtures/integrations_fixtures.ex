defmodule HeddleCore.IntegrationsFixtures do
  @moduledoc """
  A community integration for tests, with a webhook trigger that registers itself with
  the service (`New Push`) and one the person pastes by hand (`New Payment`).
  """

  @forge """
  id: forge
  name: Forge
  version: 1.0.0
  category: developer
  base_url: https://api.forge.test/
  credential:
    label: Forge
    fields:
      - {name: token, label: Token, secret: true, required: true}
      - {name: signing_secret, label: Signing secret, secret: true}
    auth: {type: bearer, token: "{{credential.token}}"}
  actions:
    - {name: Ping, request: {method: GET, path: ping}}
    - name: Create Issue
      resource: Issue
      fields:
        - name: repo
          label: Repository
          type: select
          required: true
          options_from: {request: {method: GET, path: repos}, path: items}
        - {name: title, label: Title}
        - {name: draft, label: Draft, type: boolean, default: false}
        - {name: labels, label: Labels, type: multiselect, options: [{label: Bug, value: bug}, {label: Docs, value: docs}]}
      request:
        method: POST
        path: "repos/{{fields.repo}}/issues"
        body: {title: "{{fields.title}}", draft: "{{fields.draft}}", labels: "{{fields.labels}}"}
  triggers:
    - name: New Push
      fields:
        - {name: repo, label: Repository, required: true}
      webhook:
        register:
          request:
            method: POST
            path: "repos/{{fields.repo}}/hooks"
            body: {url: "{{webhook.url}}", secret: "{{webhook.secret}}"}
          id_path: id
        unregister:
          request: {method: DELETE, path: "repos/{{fields.repo}}/hooks/{{webhook.id}}"}
        signature:
          header: X-Forge-Signature
          prefix: "sha256="
          secret: "{{webhook.secret}}"
        output:
          path: commits

    - name: New Payment
      webhook:
        signature:
          header: Pay-Signature
          secret: "{{credential.signing_secret}}"
        challenge:
          query: hub.challenge
  i18n:
    pt-BR:
      actions:
        Create Issue:
          name: Criar issue
          fields: {title: Título}
  """

  def forge_manifest, do: @forge

  @doc "Installs Forge in the workspace of `scope`, for every node code to see."
  def install_forge(scope) do
    :ok =
      HeddleCore.Integrations.install_community(scope, %{
        "integration" => "forge",
        "version" => "1.0.0",
        "manifest" => @forge
      })

    refresh = Module.concat([HeddleNodes, Community])
    if Code.ensure_loaded?(refresh), do: refresh.refresh()
    :ok
  end

  def sign(secret, body),
    do: "sha256=" <> (:crypto.mac(:hmac, :sha256, secret, body) |> Base.encode16(case: :lower))
end
