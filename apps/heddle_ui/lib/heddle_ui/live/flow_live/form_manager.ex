defmodule HeddleUI.FlowLive.FormManager do
  @moduledoc """
  The Form Trigger in the editor: its link, which the node's drawer shows, and the
  list of its fields, which the drawer edits.

  The fields are one control, `fields`, holding JSON (see `Heddle.Form`). The drawer
  shows a card per field, named `fields[i][...]`, and each change becomes that JSON
  again before it reaches the canvas, so the canvas and everyone editing see one value.
  """

  use Gettext, backend: HeddleUI.Gettext
  use Phoenix.VerifiedRoutes, endpoint: HeddleUI.Endpoint, router: HeddleUI.Router

  import Phoenix.Component, only: [assign: 3, update: 3]
  import Phoenix.LiveView, only: [put_flash: 3, push_event: 3]

  alias Heddle.Graph
  alias HeddleCore.{Flows, Forms}
  alias HeddleCore.Flows.Versions

  @type_name "Form Trigger"

  def initial_assigns, do: [form_link: nil]

  @doc "Looks up the link when the drawer opens on a Form Trigger."
  def opened(socket, %{"type" => @type_name, "id" => node_id}) do
    assign(socket, :form_link, link(socket, node_id))
  end

  def opened(socket, _node_data), do: assign(socket, :form_link, nil)

  defp link(socket, node_id) do
    %{current_scope: scope, current_flow: flow} = socket.assigns

    with %{} = flow <- Flows.get_flow(scope, flow.id),
         {:ok, form} <- Forms.link(scope, flow, node_id) do
      %{
        node_id: node_id,
        url: HeddleUI.Endpoint.url() <> ~p"/f/#{form.token}",
        test_url: ~p"/flows/#{flow.id}/forms/#{node_id}/test",
        published: published?(flow, node_id)
      }
    else
      _other -> nil
    end
  end

  defp published?(flow, node_id) do
    case Versions.published_flow(flow) do
      nil ->
        false

      published ->
        match?(%Graph.Node{type: @type_name}, published |> Graph.new() |> Graph.get(node_id))
    end
  end

  @doc """
  Turns the cards of the drawer back into the JSON of the `fields` control. A key
  follows its label until someone writes one of their own.
  """
  def encode_fields(
        %{"controls" => %{"fields" => %{"value" => before}}},
        %{"fields" => cards} = params
      )
      when is_map(cards) do
    previous = Heddle.Form.parse!(before)

    fields =
      cards
      |> Enum.sort_by(fn {index, _card} -> String.to_integer(index) end)
      |> Enum.with_index()
      |> Enum.map(fn {{_index, card}, position} ->
        auto_key(card, Enum.at(previous, position))
      end)
      |> Heddle.Form.parse!()

    Map.put(params, "fields", Heddle.Form.encode(fields))
  end

  def encode_fields(_node_data, params), do: params

  defp auto_key(card, nil), do: Map.put(card, "key", fill_key(card["key"], card["label"]))

  defp auto_key(card, previous) do
    # A key no one wrote: empty, made from the label, or the one a new field gets.
    followed =
      previous["key"] in ["", Heddle.Form.key_from_label(previous["label"])] or
        Regex.match?(~r/\Afield_\d+\z/, previous["key"])

    typed = (card["key"] || "") != previous["key"]

    cond do
      (card["key"] || "") == "" ->
        Map.put(card, "key", fill_key("", card["label"]))

      followed and not typed and (card["label"] || "") != "" ->
        Map.put(card, "key", Heddle.Form.key_from_label(card["label"]))

      true ->
        card
    end
  end

  defp fill_key(key, label) when key in [nil, ""] and is_binary(label) and label != "",
    do: Heddle.Form.key_from_label(label)

  defp fill_key(key, _label), do: key || ""

  @doc "Adds a field at the end."
  def add_field(socket) do
    change_fields(socket, fn fields ->
      fields ++
        [%{"key" => unique_key(fields), "label" => "", "type" => "text", "required" => false}]
    end)
  end

  @doc "Removes the field at `index`."
  def remove_field(socket, index) do
    change_fields(socket, &List.delete_at(&1, index))
  end

  @doc "Moves the field at `index` up or down."
  def move_field(socket, index, direction) do
    change_fields(socket, fn fields ->
      target = if direction == "up", do: index - 1, else: index + 1

      if target < 0 or target >= length(fields) do
        fields
      else
        field = Enum.at(fields, index)
        fields |> List.delete_at(index) |> List.insert_at(target, field)
      end
    end)
  end

  defp unique_key(fields) do
    keys = MapSet.new(fields, & &1["key"])

    (length(fields) + 1)
    |> Stream.iterate(&(&1 + 1))
    |> Stream.map(&"field_#{&1}")
    |> Enum.find(&(&1 not in keys))
  end

  defp change_fields(%{assigns: %{can_edit: false}} = socket, _fun), do: socket

  defp change_fields(
         %{assigns: %{editing_node_data: %{"controls" => %{"fields" => _}}}} = socket,
         fun
       ) do
    node_data = socket.assigns.editing_node_data

    fields =
      node_data |> get_in(["controls", "fields", "value"]) |> Heddle.Form.parse!() |> fun.()

    json = Heddle.Form.encode(fields)

    socket
    |> update(:editing_node_data, &put_in(&1, ["controls", "fields", "value"], json))
    |> push_event("update_node_data", %{nodeId: node_data["id"], data: %{"fields" => json}})
  end

  defp change_fields(socket, _fun), do: socket

  @doc "Gives the form a new link, so the old one stops working."
  def regenerate(socket) do
    %{current_scope: scope, current_flow: flow, form_link: link} = socket.assigns

    case link && Forms.regenerate(scope, flow, link.node_id) do
      {:ok, _form} ->
        socket
        |> assign(:form_link, link(socket, link.node_id))
        |> put_flash(:info, gettext("The form has a new link. The old one no longer works."))

      _other ->
        put_flash(socket, :error, gettext("Your role in this workspace can't change this form."))
    end
  end

  @doc "Creates a Spool table with a column for each field."
  def create_table(socket) do
    %{current_scope: scope, current_flow: flow, form_link: link, editing_node_data: node} =
      socket.assigns

    flow = Flows.get_flow(scope, flow.id)
    name = table_name(node)

    case link && flow && Forms.create_table(scope, flow, link.node_id, name) do
      {:ok, table} ->
        put_flash(
          socket,
          :info,
          gettext(
            "Created the Spool table %{name}. Save answers in it with a Spool: Insert Rows node.",
            name: table.name
          )
        )

      {:error, {:limit, max}} ->
        put_flash(socket, :error, gettext("A workspace keeps up to %{max} tables.", max: max))

      {:error, %Ecto.Changeset{}} ->
        put_flash(
          socket,
          :error,
          gettext("There is already a Spool table named %{name}.", name: name)
        )

      _other ->
        put_flash(socket, :error, gettext("Your role in this workspace can't create tables."))
    end
  end

  defp table_name(node) do
    title = node |> get_in(["controls", "title", "value"]) |> to_string() |> String.trim()
    if title == "", do: node["label"] || "Form", else: title
  end
end
