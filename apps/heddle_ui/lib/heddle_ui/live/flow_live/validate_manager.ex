defmodule HeddleUI.FlowLive.ValidateManager do
  @moduledoc """
  The Validate node in the editor's drawer: its rules as cards, or its schema as JSON
  for what only JSON says. See `HeddleUI.FlowLive.ValidateRules`.

  The schema is one control, `validation_schema`, holding JSON. The cards are named
  `validation_schema[i][...]`, and each change becomes that JSON again before it
  reaches the canvas, as the fields of a Form Trigger do (see
  `HeddleUI.FlowLive.FormManager`).
  """

  import Phoenix.Component, only: [assign: 3, update: 3]
  import Phoenix.LiveView, only: [push_event: 3]

  alias Heddle.Graph
  alias HeddleCore.Flows
  alias HeddleUI.FlowLive.ValidateRules

  @type_name "Validate"
  @control "validation_schema"

  def initial_assigns, do: [validate_json: false, validate_form_fields: nil]

  @doc """
  Opens the drawer on the cards, and finds the fields of the flow's form, which the
  rules can start from.
  """
  def opened(socket, %{"type" => @type_name}) do
    socket
    |> assign(:validate_json, false)
    |> assign(:validate_form_fields, form_fields(socket))
  end

  def opened(socket, _node_data), do: assign(socket, :validate_form_fields, nil)

  defp form_fields(socket) do
    %{current_scope: scope, current_flow: flow} = socket.assigns

    with %{} = flow <- Flows.get_flow(scope, flow.id),
         [form | _] <- flow |> Graph.new() |> Graph.of_type(HeddleCore.Forms.node_type()),
         [_ | _] = fields <- Heddle.Form.parse!(form.controls["fields"]) do
      fields
    else
      _other -> nil
    end
  end

  @doc "Turns the cards of the drawer back into the JSON of the schema."
  def encode(%{"type" => @type_name}, %{@control => %{} = cards} = params) do
    rules =
      cards
      |> Enum.sort_by(fn {index, _card} -> String.to_integer(index) end)
      |> Enum.map(fn {_index, card} -> card end)

    Map.put(params, @control, ValidateRules.to_schema(rules))
  end

  def encode(_node_data, params), do: params

  @doc "Adds a field at the end."
  def add_rule(socket) do
    change_rules(socket, fn rules ->
      [rule] = ValidateRules.from_form([%{"key" => unique_key(rules), "type" => "text"}])
      rules ++ [%{rule | "required" => true}]
    end)
  end

  @doc "Removes the field at `index`."
  def remove_rule(socket, index), do: change_rules(socket, &List.delete_at(&1, index))

  @doc """
  Starts the rules from the fields of the flow's form, and checks what it sends.
  """
  def use_form(%{assigns: %{validate_form_fields: [_ | _] = fields}} = socket) do
    socket
    |> change_rules(fn _rules -> ValidateRules.from_form(fields) end)
    |> change_control("validation_data", "{{form}}")
  end

  def use_form(socket), do: socket

  @doc "Shows the schema as JSON, or as cards again when they can show it."
  def toggle_json(socket), do: update(socket, :validate_json, &(not &1))

  defp unique_key(rules) do
    keys = MapSet.new(rules, & &1["key"])

    (length(rules) + 1)
    |> Stream.iterate(&(&1 + 1))
    |> Stream.map(&"field_#{&1}")
    |> Enum.find(&(&1 not in keys))
  end

  defp change_rules(%{assigns: %{can_edit: false}} = socket, _fun), do: socket

  defp change_rules(socket, fun) do
    value = get_in(socket.assigns.editing_node_data, ["controls", @control, "value"])

    case ValidateRules.from_schema(value) do
      {:ok, rules} -> change_control(socket, @control, ValidateRules.to_schema(fun.(rules)))
      :complex -> socket
    end
  end

  defp change_control(%{assigns: %{can_edit: false}} = socket, _name, _value), do: socket

  defp change_control(socket, name, value) do
    node_data = socket.assigns.editing_node_data

    if get_in(node_data, ["controls", name]) do
      socket
      |> update(:editing_node_data, &put_in(&1, ["controls", name, "value"], value))
      |> push_event("update_node_data", %{nodeId: node_data["id"], data: %{name => value}})
    else
      socket
    end
  end
end
