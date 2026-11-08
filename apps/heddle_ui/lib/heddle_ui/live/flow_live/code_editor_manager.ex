defmodule HeddleUI.FlowLive.CodeEditorManager do
  @moduledoc """
  Socket reducers and state management for the Monaco/Code Editor modal inside `FlowLive.Editor`.
  """

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [push_event: 3]

  alias HeddleUI.FlowLive.NodeCode

  @doc """
  Returns the default socket assigns for the code editor modal.
  """
  def initial_assigns do
    [
      modal_open: false,
      current_node_id: nil,
      current_code_elixir: "",
      current_code_python: "",
      current_code_tab: "elixir",
      current_field_name: nil,
      current_language: "elixir",
      available_variables: [],
      # What the code was when it opened, to tell whether someone changed it since.
      code_base: nil,
      code_conflict: nil,
      code_revision: 0
    ]
  end

  @doc """
  Opens the code editor modal triggered from a canvas node event.
  """
  def open_from_event(
        socket,
        %{"nodeId" => node_id, "fieldName" => field_name, "language" => _language} = params
      ) do
    socket
    |> open(NodeCode.resolve(params), field_name)
    |> assign(current_node_id: node_id, available_variables: params["variables"] || [])
  end

  def open_from_event(socket, %{"nodeId" => node_id, "code" => code}) do
    open_from_event(socket, %{
      "nodeId" => node_id,
      "code" => code,
      "fieldName" => "code",
      "language" => "elixir",
      "variables" => []
    })
  end

  @doc """
  Opens the code editor modal triggered from the node configuration drawer.
  """
  def open_from_config(socket, %{"field-name" => field_name}) do
    code = NodeCode.from_controls(socket.assigns.editing_node_data["controls"] || %{})

    open(socket, code, field_name)
  end

  defp open(socket, code, field_name) do
    assign(socket,
      code_base: %{elixir: code.code_elixir, python: code.code_python},
      code_conflict: nil,
      modal_open: true,
      current_code_elixir: code.code_elixir,
      current_code_python: code.code_python,
      current_code_tab: code.language,
      current_field_name: field_name,
      current_language: code.language
    )
  end

  @doc """
  Switches the active language (elixir vs python).
  """
  def switch_language(socket, lang) do
    assign(socket, current_language: lang)
  end

  @doc """
  Switches the active editor tab.
  """
  def switch_tab(socket, tab) do
    assign(socket, current_code_tab: tab)
  end

  @doc """
  Closes the code editor modal and resets buffer assigns.
  """
  def close(socket) do
    assign(socket,
      modal_open: false,
      current_node_id: nil,
      current_code_elixir: "",
      current_code_python: "",
      current_field_name: nil
    )
  end

  @doc """
  Saves the edited code. Updates either the node configuration drawer data or pushes
  an `update_node_code` event to the canvas.
  """
  def save(socket, %{"code_elixir" => code_elixir, "code_python" => code_python} = params) do
    node_id = socket.assigns.current_node_id
    field_name = socket.assigns.current_field_name
    theirs = if params["overwrite"] == "true", do: nil, else: changed_since_open(socket)

    cond do
      theirs ->
        assign(socket, code_conflict: theirs)

      socket.assigns.config_modal_open ->
        save_in_drawer(socket, code_elixir, code_python)

      true ->
        save_on_canvas(socket, node_id, field_name, code_elixir, code_python)
    end
  end

  @doc "Takes the code someone else saved, in place of what was being typed."
  def load_theirs(%{assigns: %{code_conflict: %{} = theirs}} = socket) do
    assign(socket,
      current_code_elixir: theirs.elixir,
      current_code_python: theirs.python,
      code_base: theirs,
      code_conflict: nil,
      # A new editor, with their code in it.
      code_revision: socket.assigns.code_revision + 1
    )
  end

  def load_theirs(socket), do: socket

  # The last one to save wins, but nobody overwrites someone else's code unknowingly.
  defp changed_since_open(%{assigns: %{code_base: %{} = base, current_node_id: id}} = socket)
       when is_binary(id) do
    with %{} = flow <-
           HeddleCore.Flows.get_flow(socket.assigns.current_scope, socket.assigns.current_flow.id),
         %{} = node <- Enum.find(flow.nodes || [], &(to_string(&1["id"]) == id)) do
      now = %{
        elixir: get_in(node, ["controls", "code_elixir"]) || "",
        python: get_in(node, ["controls", "code_python"]) || ""
      }

      if now != base and not (now.elixir == "" and now.python == ""), do: now
    else
      _none -> nil
    end
  end

  defp changed_since_open(_socket), do: nil

  defp save_in_drawer(socket, code_elixir, code_python) do
    updated_node_data =
      socket.assigns.editing_node_data
      |> put_in(["controls", "code_elixir", "value"], code_elixir)
      |> put_in(["controls", "code_python", "value"], code_python)
      |> clear_older_code()

    assign(socket,
      modal_open: false,
      current_code_elixir: "",
      current_code_python: "",
      current_field_name: nil,
      code_conflict: nil,
      editing_node_data: updated_node_data
    )
  end

  defp save_on_canvas(socket, node_id, field_name, code_elixir, code_python) do
    socket
    |> push_event("update_node_code", %{
      nodeId: node_id,
      code_elixir: code_elixir,
      code_python: code_python,
      fieldName: field_name
    })
    |> assign(
      modal_open: false,
      current_node_id: nil,
      current_code_elixir: "",
      current_code_python: "",
      current_field_name: nil,
      code_conflict: nil
    )
  end

  # The code now lives in the fields of each language. Left in place, the older
  # field would come back at run time if that code were cleared.
  defp clear_older_code(%{"controls" => %{"code" => _control}} = node_data) do
    put_in(node_data, ["controls", "code", "value"], "")
  end

  defp clear_older_code(node_data), do: node_data
end
