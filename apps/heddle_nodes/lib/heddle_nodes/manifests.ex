defmodule HeddleNodes.Manifests do
  @moduledoc """
  The integrations written as manifests, in `priv/integrations/*.yaml`. See
  `Bobbin.Integration` for the format.

  Each action becomes a node module at compile time, named after the integration and
  the action, like `HeddleNodes.Manifests.Slack.SendMessage`. Its node works like any
  other service node: it takes a credential and answers through `success` and `error`.
  """

  alias Bobbin.Integration, as: Manifest
  alias HeddleNodes.Integration
  alias HeddleNodes.Template

  @dir Path.expand("../../priv/integrations", __DIR__)
  @paths @dir |> Path.join("*.yaml") |> Path.wildcard() |> Enum.sort()

  for path <- @paths, do: @external_resource(path)
  @external_resource @dir

  @manifests Map.new(@paths, fn path ->
               manifest = Manifest.load!(path)
               {manifest.id, manifest}
             end)

  @doc false
  def __mix_recompile__? do
    @dir |> Path.join("*.yaml") |> Path.wildcard() |> Enum.sort() != @paths
  end

  @doc "Every manifest, by id."
  def all, do: @manifests

  @doc "The manifest with `id`."
  def get(id), do: Map.fetch!(@manifests, id)

  @doc "The module of each action of the manifest `id`, in its order."
  def modules(id) do
    manifest = get(id)
    Enum.map(manifest.actions, &module_name(manifest, &1))
  end

  @doc "The module of each action of every manifest."
  def modules, do: @manifests |> Map.keys() |> Enum.sort() |> Enum.flat_map(&modules/1)

  defdelegate module_name(manifest, action), to: HeddleNodes.Manifests.Definition

  @doc """
  The credential kinds the manifests declare, in the form `HeddleCore.Credentials`
  takes. `HeddleCore.Credentials` adds the ones it doesn't already have.
  """
  def credential_kinds do
    for {_id, %{credential: %{} = credential}} <- @manifests, do: credential_kind(credential)
  end

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

  @doc "The credential kinds of the manifests and of the community integrations."
  def all_credential_kinds do
    Enum.uniq_by(credential_kinds() ++ HeddleNodes.Community.credential_kinds(), & &1.id)
  end

  defdelegate definition(manifest, action), to: HeddleNodes.Manifests.Definition

  @doc "Runs `action` of the manifest `id` with the node's `context`."
  def run(id, action_name, context) when is_binary(id), do: run(get(id), action_name, context)

  def run(manifest, action_name, context) do
    action = Manifest.action(manifest, action_name)
    kind = manifest.credential && manifest.credential.kind

    request = fn credential ->
      Bobbin.Integration.Request.run(
        manifest,
        action_name,
        fields(action, context),
        credential,
        Integration.req_options([])
      )
    end

    oauth? = match?(%{auth: %{"type" => "oauth2"}}, manifest.credential)

    cond do
      kind && oauth? ->
        Integration.run(context, kind, fn credential ->
          case request.(credential) do
            # The service refused the token: renew it and try once more.
            {:error, message} = error ->
              if String.ends_with?(message, "answered 401") do
                with {:ok, renewed} <- Integration.credential(context, kind, refresh: true),
                     do: request.(renewed)
              else
                error
              end

            result ->
              result
          end
        end)

      kind ->
        Integration.run(context, kind, request)

      true ->
        case request.(%{}) do
          {:ok, result} -> Integration.success(context, result)
          {:error, message} -> Integration.failure(context, message)
        end
    end
  end

  # A field the node doesn't set takes its default, which may point at the last step.
  defp fields(action, context) do
    Map.new(action.fields, fn field ->
      template = context[field.name] || field.default
      {field.name, Template.render(template, context)}
    end)
  end

  for {_id, manifest} <- @manifests, action <- manifest.actions do
    defmodule HeddleNodes.Manifests.Definition.module_name(manifest, action) do
      @moduledoc false
      use Bobbin.Node

      @manifest_id manifest.id
      @action_name action.name
      @definition HeddleNodes.Manifests.Definition.definition(manifest, action)

      @impl true
      def definition, do: @definition

      @impl true
      def handler(context, _input) do
        HeddleNodes.Manifests.run(@manifest_id, @action_name, context)
      end
    end
  end
end
