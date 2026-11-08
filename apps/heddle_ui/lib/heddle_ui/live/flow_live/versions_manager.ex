defmodule HeddleUI.FlowLive.VersionsManager do
  @moduledoc """
  Publishing and the history of versions in the editor: the state the header shows,
  the history panel, the preview of a version and the publish dialog.

  The canvas holds the draft, which production doesn't run until someone publishes
  it, see `HeddleCore.Flows.Versions`. A version is previewed on a canvas of its own,
  over the draft, so looking at one never touches what is being edited.
  """

  use Gettext, backend: HeddleUI.Gettext

  import Phoenix.Component, only: [assign: 2, to_form: 2]
  import Phoenix.LiveView, only: [push_event: 3, put_flash: 3, stream: 4]

  alias Heddle.Graph
  alias Heddle.Graph.Diff
  alias Heddle.Graph.Layout
  alias HeddleCore.Flows
  alias HeddleCore.Flows.{Version, Versions}
  alias HeddleUI.AIChat

  def initial_assigns(flow) do
    [
      versions_open: false,
      versions_count: 0,
      version_preview: nil,
      publish_open: false,
      publish_form: publish_form(),
      published_version: Versions.published_version(flow)
    ]
  end

  @doc "Sets up the stream of the history, which is empty until it opens."
  def mount(socket), do: stream(socket, :versions, [], reset: true)

  @doc """
  What the header says of the flow: `:unpublished`, `:changed` when the draft isn't
  what is published, or `:published`.
  """
  def status(%{published_version: nil}), do: :unpublished

  def status(%{has_changes: true}), do: :changed

  def status(%{published_version: version, current_flow: flow}) do
    if Versions.same_graph?(flow, version), do: :published, else: :changed
  end

  ## History

  def toggle(socket) do
    if socket.assigns.versions_open, do: close(socket), else: open(socket)
  end

  def open(socket) do
    socket
    |> assign(versions_open: true)
    |> load()
  end

  def close(socket) do
    socket
    |> assign(versions_open: false)
    |> close_preview()
  end

  @doc "A version was kept or published: the history and the header catch up."
  def refresh(socket) do
    socket =
      assign(socket, published_version: Versions.published_version(socket.assigns.current_flow))

    if socket.assigns.versions_open, do: load(socket), else: socket
  end

  defp load(socket) do
    %{current_scope: scope, current_flow: flow} = socket.assigns

    case Versions.list_versions(scope, flow) do
      {:ok, entries} ->
        socket
        |> assign(versions_count: length(entries))
        |> stream(:versions, Enum.map(entries, &row/1), reset: true)

      {:error, _reason} ->
        socket
    end
  end

  defp row(%{version: version, diff: diff, contributors: contributors}) do
    %{
      id: version.id,
      version: version,
      summary: Diff.summary(diff),
      contributors: contributors
    }
  end

  ## Preview

  def preview(socket, id) do
    case Versions.get_version(socket.assigns.current_scope, socket.assigns.current_flow, id) do
      %Version{} = version ->
        assign(socket, version_preview: %{version: version})

      nil ->
        put_flash(socket, :error, gettext("That version was not found."))
    end
  end

  def close_preview(socket), do: assign(socket, version_preview: nil)

  @doc """
  What the preview canvas draws: the version, what it changed from the one before
  marked on its nodes, and the nodes it removed as ghosts where they were.
  """
  def preview_graph(%{version_preview: %{version: version}}) do
    diff = Diff.between(Versions.previous(version) || %{}, version)
    ghosts = diff.nodes.removed
    nodes = version.nodes ++ ghosts

    %{
      nodes: Layout.place(nodes, version.connections),
      connections: Graph.normalize_connections(version.connections),
      comments: version.comments,
      definitions: AIChat.node_definitions(),
      diff: Diff.node_states(diff)
    }
  end

  def preview_graph(_assigns), do: nil

  ## Publishing

  def open_publish(socket), do: assign(socket, publish_open: true, publish_form: publish_form())

  def close_publish(socket), do: assign(socket, publish_open: false)

  @doc """
  Publishes what the canvas holds, `data`, with the note typed in the dialog.
  """
  def publish(socket, data, params) do
    %{current_scope: scope, current_flow: flow} = socket.assigns

    case Versions.save_and_publish(scope, flow, data, params) do
      {:ok, %{flow: flow, version: version}} ->
        socket
        |> assign(current_flow: flow, has_changes: false, publish_open: false)
        |> assign(published_version: version)
        |> refresh()
        |> put_flash(:info, gettext("Version %{number} is published.", number: version.number))

      {:error, _stage, :forbidden} ->
        put_flash(socket, :error, gettext("Your role in this workspace can't publish flows."))

      {:error, :save, _reason} ->
        put_flash(socket, :error, gettext("The flow could not be saved, so it wasn't published."))

      {:error, :publish, _reason} ->
        put_flash(socket, :error, gettext("The flow could not be published."))
    end
  end

  @doc "Puts an older version back in production, leaving the draft as it is."
  def publish_version(socket, id) do
    %{current_scope: scope, current_flow: flow} = socket.assigns

    case Versions.publish_version(scope, flow, id) do
      {:ok, version} ->
        socket
        |> assign(current_flow: Flows.get_flow!(flow.id), published_version: version)
        |> refresh()
        |> close_preview()
        |> put_flash(
          :info,
          gettext("Version %{number} is published, with what version %{source} had.",
            number: version.number,
            source: version.source && version.source.number
          )
        )

      {:error, :forbidden} ->
        put_flash(socket, :error, gettext("Your role in this workspace can't publish flows."))

      {:error, _reason} ->
        put_flash(socket, :error, gettext("That version could not be published."))
    end
  end

  @doc """
  Replaces the draft with a version. The draft it had is kept as a checkpoint, so this
  can be undone from the history too.
  """
  def restore(socket, id) do
    %{current_scope: scope, current_flow: flow} = socket.assigns

    case Versions.restore(scope, flow, id) do
      {:ok, flow} ->
        socket
        |> assign(current_flow: flow, has_changes: false)
        |> close_preview()
        |> refresh()
        |> push_event("load_graph_data", %{
          nodes: Layout.place(flow.nodes, flow.connections),
          connections: Graph.normalize_connections(flow.connections),
          comments: flow.comments,
          definitions: AIChat.node_definitions()
        })
        |> put_flash(:info, gettext("The draft now has what that version had."))

      {:error, :forbidden} ->
        put_flash(socket, :error, gettext("Your role in this workspace can't change this flow."))

      {:error, _reason} ->
        put_flash(socket, :error, gettext("That version could not be restored."))
    end
  end

  defp publish_form, do: to_form(%{"note" => ""}, as: :publish)
end
