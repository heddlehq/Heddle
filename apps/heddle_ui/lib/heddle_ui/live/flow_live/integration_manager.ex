defmodule HeddleUI.FlowLive.IntegrationManager do
  @moduledoc """
  What the drawer of an integration's node shows besides its fields: the address of a
  webhook trigger (see `HeddleCore.Integrations.Hooks`), and the options a field lists
  from the service (`options_from` in its manifest), which load when someone asks,
  with the credential and the other fields the node has so far.

  A multiselect reaches the canvas as a JSON list, which Bobbin reads as one.
  """

  use Gettext, backend: HeddleUI.Gettext

  import Phoenix.Component, only: [assign: 3, update: 3]

  alias Heddle.Graph
  alias HeddleCore.Flows
  alias HeddleCore.Flows.Versions
  alias HeddleCore.Integrations.Hooks
  alias HeddleNodes.Manifests

  def initial_assigns, do: [hook_link: nil, field_options: %{}]

  @doc "Looks up the address when the drawer opens on a webhook trigger."
  def opened(socket, node_data) do
    socket
    |> assign(:field_options, %{})
    |> assign(:hook_link, hook_link(socket, node_data))
  end

  defp hook_link(socket, %{"type" => type, "id" => node_id}) when is_binary(type) do
    case HeddleNodes.Nodes.get_node(type) do
      %{webhook: %{manual: manual}, title: title} ->
        flow = socket.assigns.current_flow
        hook = Hooks.get(flow.id, node_id)

        %{
          service: title |> String.split(":") |> List.first(),
          manual: manual,
          url: hook && Hooks.url(hook),
          error: hook && hook.error,
          published: published?(flow, node_id, type)
        }

      _other ->
        nil
    end
  end

  defp hook_link(_socket, _node_data), do: nil

  defp published?(flow, node_id, type) do
    with %{} = flow <- Flows.get_flow(flow.id),
         %{} = published <- Versions.published_flow(flow) do
      match?(%Graph.Node{type: ^type}, published |> Graph.new() |> Graph.get(node_id))
    else
      _other -> false
    end
  end

  @doc """
  Lists the options of `field` from the service, for the node being edited. Only
  those who edit the flow may, since it calls the service with a credential.
  """
  def load_options(%{assigns: %{can_edit: false}} = socket, _field), do: socket

  def load_options(socket, field) do
    %{editing_node_data: node_data, current_scope: scope} = socket.assigns

    result =
      case Manifests.step(node_data["type"]) do
        %{manifest: manifest, step: step} ->
          context =
            node_data["controls"]
            |> Map.new(fn {key, control} -> {key, control["value"]} end)
            |> Map.put("workspace_id", scope.workspace && scope.workspace.id)

          Manifests.options(manifest, step.name, field, context)

        nil ->
          {:error, gettext("This node no longer has an integration.")}
      end

    entry =
      case result do
        {:ok, options} -> %{options: options}
        {:error, message} -> %{error: message}
      end

    update(socket, :field_options, &Map.put(&1, field, entry))
  end

  @doc """
  Turns what the drawer sent for each multiselect (a list, with an empty first item
  so none selected still sends something) into the JSON list the control keeps.
  """
  def encode(%{"controls" => controls}, params) when is_map(controls) do
    for {key, %{"type" => "multiselect"}} <- controls, is_list(params[key]), reduce: params do
      params -> Map.put(params, key, params[key] |> Enum.reject(&(&1 == "")) |> Jason.encode!())
    end
  end

  def encode(_node_data, params), do: params

  @doc "The values a multiselect control holds, from its JSON list or a comma list."
  def selected(value) when is_list(value), do: Enum.map(value, &to_string/1)

  def selected(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, list} when is_list(list) -> Enum.map(list, &to_string/1)
      _other -> value |> String.split(",", trim: true) |> Enum.map(&String.trim/1)
    end
  end

  def selected(_value), do: []

  @doc "The label of a field in the user's language, when the manifest translates it."
  def label(type, key, fallback) do
    # Gettext says pt_BR; manifests, like the web, pt-BR.
    locale = HeddleUI.Gettext |> Gettext.get_locale() |> String.replace("_", "-")

    case HeddleNodes.Nodes.get_node(type) do
      %{i18n: %{^locale => %{fields: %{^key => label}}}} -> label
      _other -> fallback
    end
  end
end
