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
    for {_id, %{credential: %{} = credential}} <- @manifests do
      %{
        id: credential.kind,
        label: credential.label,
        fields:
          Enum.map(credential.fields, fn field ->
            %{
              name: field.name,
              label: field.label,
              secret: field.secret,
              required: field.required
            }
          end)
      }
    end
  end

  defdelegate definition(manifest, action), to: HeddleNodes.Manifests.Definition

  @doc "Runs `action` of the manifest `id` with the node's `context`."
  def run(id, action_name, context) do
    manifest = get(id)
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

    if kind do
      Integration.run(context, kind, request)
    else
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
