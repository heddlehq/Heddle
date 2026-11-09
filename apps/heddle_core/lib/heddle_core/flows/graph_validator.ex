defmodule HeddleCore.Flows.GraphValidator do
  @moduledoc """
  Validates persisted workflow graph payloads.

  The validator intentionally keeps `heddle_core` decoupled from the nodes
  app. Callers can provide a manifest module with `:manifest`; otherwise the
  runtime-configured manifest or `HeddleNodes` is used when available.
  """

  alias Heddle.Graph
  alias Heddle.Graph.Settings
  alias HeddleCore.Flows.Schedule

  @node_keys ~w(id type label controls settings position)
  @connection_keys ~w(source sourceOutput target targetInput)
  @comment_keys ~w(id kind color text position width height manual nodes)
  @comment_kinds ~w(title text note section)
  @comment_colors ~w(default yellow green blue red)

  @doc "The fields a persisted node may have."
  def node_keys, do: @node_keys

  def validate(nodes, connections, opts \\ []) do
    with :ok <- validate_list(:nodes, nodes),
         :ok <- validate_list(:connections, connections) do
      validate_graph(Graph.normalize_nodes(nodes), Graph.normalize_connections(connections), opts)
    end
  end

  @doc "Validates what is written on the canvas, which isn't part of the graph."
  def validate_comments(comments) do
    with :ok <- validate_list(:comments, comments) do
      ids = Enum.map(comments, &to_string(&1["id"]))

      cond do
        length(Enum.uniq(ids)) != length(ids) ->
          {:error, :comments, "contains duplicate comment ids"}

        Enum.all?(comments, &valid_comment?/1) ->
          :ok

        true ->
          {:error, :comments, "contains an invalid comment"}
      end
    end
  end

  defp valid_comment?(comment) do
    not unknown_keys?(comment, @comment_keys) and present_id?(comment["id"]) and
      comment["kind"] in @comment_kinds and comment["color"] in @comment_colors and
      is_binary(comment["text"]) and valid_position?(comment["position"]) and
      positive_number?(comment["width"]) and positive_number?(comment["height"]) and
      valid_section_fields?(comment)
  end

  # What a section holds, see `Heddle.Graph.Section`. Only a section has it.
  defp valid_section_fields?(%{"kind" => "section"} = comment) do
    comment["manual"] in [nil, true, false] and
      (is_nil(comment["nodes"]) or
         (is_list(comment["nodes"]) and Enum.all?(comment["nodes"], &present_id?/1)))
  end

  defp valid_section_fields?(comment) do
    not Map.has_key?(comment, "manual") and not Map.has_key?(comment, "nodes")
  end

  defp validate_graph([], [], _opts), do: :ok

  defp validate_graph(nodes, connections, opts) do
    with {:ok, definitions} <- definitions(opts),
         :ok <- validate_nodes(nodes, definitions, opts),
         :ok <- validate_connections(connections, nodes, definitions) do
      :ok
    end
  end

  defp validate_list(field, value) when is_list(value) do
    if Enum.all?(value, &is_map/1) do
      :ok
    else
      {:error, field, "must contain only objects"}
    end
  end

  defp validate_list(field, _value), do: {:error, field, "must be a list"}

  @doc """
  The definitions of the nodes a flow can use, by name, from the manifest in
  `:manifest` or the configured one.
  """
  def definitions(opts \\ []) do
    manifest =
      Keyword.get_lazy(opts, :manifest, fn ->
        Application.get_env(:heddle_core, :graph_manifest, HeddleNodes)
      end)

    if Code.ensure_loaded?(manifest) and function_exported?(manifest, :get_definitions, 0) do
      definitions =
        manifest.get_definitions()
        |> Map.new(fn definition -> {Map.fetch!(definition, :name), definition} end)

      {:ok, definitions}
    else
      {:error, :nodes, "node manifest is unavailable"}
    end
  end

  # A draft (`draft: true`) may hold what is still being typed, such as half a cron
  # expression: it only has to be a graph. What runs is checked in full when published.
  defp validate_nodes(nodes, definitions, opts) do
    draft? = Keyword.get(opts, :draft, false)

    node_ids = MapSet.new(nodes, & &1["id"])

    Enum.reduce_while(nodes, :ok, fn node, :ok ->
      cond do
        unknown_keys?(node, @node_keys) ->
          {:halt, {:error, :nodes, "contains unknown node fields"}}

        not present_id?(node["id"]) ->
          {:halt, {:error, :nodes, "contains a node without id"}}

        MapSet.size(node_ids) != length(nodes) ->
          {:halt, {:error, :nodes, "contains duplicate node ids"}}

        not present_string?(node["type"]) ->
          {:halt, {:error, :nodes, "contains a node without type"}}

        invalid_position?(node) ->
          {:halt, {:error, :nodes, "contains a node with invalid position"}}

        not is_map(node["controls"]) ->
          {:halt, {:error, :nodes, "contains a node without controls"}}

        not Settings.valid?(node["settings"]) ->
          {:halt, {:error, :nodes, "contains a node with invalid settings"}}

        not Map.has_key?(definitions, node["type"]) ->
          {:halt, {:error, :nodes, "contains unknown node type"}}

        not draft? and invalid_schedule?(node) ->
          {:halt, {:error, :nodes, "contains a Schedule node with an invalid cron expression"}}

        message = not draft? && invalid_form(node) ->
          {:halt, {:error, :nodes, "contains a Form Trigger that #{message}"}}

        message = not draft? && invalid_schema(node) ->
          {:halt, {:error, :nodes, "contains a Validate node whose #{message}"}}

        not draft? and subflow_without_flow?(node) ->
          {:halt, {:error, :nodes, "contains a Subflow with no flow picked"}}

        true ->
          {:cont, :ok}
      end
    end)
  end

  # Only the canvas needs a position, and it places a node that has none.
  defp invalid_position?(node) do
    not is_nil(node["position"]) and not valid_position?(node["position"])
  end

  defp invalid_schedule?(%{"type" => "Schedule", "controls" => %{"cron" => cron}}) do
    not Schedule.valid?(cron)
  end

  defp invalid_schedule?(_node), do: false

  # A form has to be complete to be published, see `Heddle.Form`.
  defp invalid_form(%{"type" => "Form Trigger", "controls" => controls}) do
    with {:ok, fields} <- Heddle.Form.parse(controls["fields"]),
         :ok <- Heddle.Form.validate(fields) do
      nil
    else
      {:error, message} -> message
    end
  end

  defp invalid_form(_node), do: nil

  # The schema of a Validate node is plain JSON, so it is checked here, see
  # `Heddle.Schema`.
  defp invalid_schema(%{"type" => "Validate", "controls" => controls}) do
    case Heddle.Schema.parse(controls["validation_schema"]) do
      {:ok, _schema} -> nil
      {:error, message} -> "schema is wrong: #{message}"
    end
  end

  defp invalid_schema(_node), do: nil

  defp subflow_without_flow?(%{"type" => "Subflow", "controls" => controls}) do
    not present_id?(controls["subflow_id"])
  end

  defp subflow_without_flow?(_node), do: false

  defp validate_connections(connections, nodes, definitions) do
    nodes_by_id = Map.new(nodes, &{&1["id"], &1})

    Enum.reduce_while(connections, :ok, fn connection, :ok ->
      source_node = nodes_by_id[connection["source"]]
      target_node = nodes_by_id[connection["target"]]

      cond do
        unknown_keys?(connection, @connection_keys) ->
          {:halt, {:error, :connections, "contains unknown connection fields"}}

        missing_connection_field?(connection) ->
          {:halt, {:error, :connections, "contains an incomplete connection"}}

        is_nil(source_node) or is_nil(target_node) ->
          {:halt, {:error, :connections, "references a missing node"}}

        not output_exists?(definitions, source_node, connection["sourceOutput"]) ->
          {:halt, {:error, :connections, "references an unknown source output"}}

        not input_exists?(definitions, target_node, connection["targetInput"]) ->
          {:halt, {:error, :connections, "references an unknown target input"}}

        true ->
          {:cont, :ok}
      end
    end)
  end

  defp missing_connection_field?(connection) do
    not present_id?(connection["source"]) or not present_id?(connection["target"]) or
      not present_string?(connection["sourceOutput"]) or
      not present_string?(connection["targetInput"])
  end

  # Settings can give any node an `error` output, see `Heddle.Graph.Settings`.
  defp output_exists?(definitions, node, output) do
    (output == "error" and Settings.error_output?(node["settings"])) or
      defined_output?(definitions, node, output)
  end

  defp defined_output?(definitions, node, output) do
    definitions
    |> Map.fetch!(node["type"])
    |> Map.get(:outputs, [])
    |> Enum.map(&port_id/1)
    |> Enum.member?(to_string(output))
  end

  defp input_exists?(definitions, node, input) do
    definitions
    |> Map.fetch!(node["type"])
    |> Map.get(:inputs, [])
    |> Enum.map(&port_id/1)
    |> Enum.member?(to_string(input))
  end

  defp port_id(port) when is_atom(port), do: Atom.to_string(port)
  defp port_id(port) when is_binary(port), do: port
  defp port_id(%{} = port), do: to_string(port[:id] || port["id"])

  defp valid_position?(%{"x" => x, "y" => y}), do: number?(x) and number?(y)
  defp valid_position?(%{x: x, y: y}), do: number?(x) and number?(y)
  defp valid_position?(_position), do: false

  defp number?(value), do: is_integer(value) or is_float(value)

  defp positive_number?(value), do: number?(value) and value > 0

  defp present_id?(value) when is_binary(value), do: String.trim(value) != ""
  defp present_id?(value) when is_integer(value), do: true
  defp present_id?(_value), do: false

  defp present_string?(value) when is_binary(value), do: String.trim(value) != ""
  defp present_string?(_value), do: false

  defp unknown_keys?(map, allowed_keys) do
    map
    |> Map.keys()
    |> Enum.any?(&(to_string(&1) not in allowed_keys))
  end
end
