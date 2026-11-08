defmodule HeddleCore.Flows.Import do
  @moduledoc """
  Reads a flow from a JSON file, to put it on the canvas in place of the one there.

  It takes what Heddle saves, `{"nodes", "connections", "comments"}`, and what the
  API answers for a flow, the same inside `"data"`. The flow must pass the checks
  made before a flow is saved, see `HeddleCore.Flows.GraphValidator`.

  The fields that pick a credential are emptied: an id from another install, or
  another person, means nothing here, and the person importing picks their own.
  """

  alias Heddle.Graph
  alias HeddleCore.Flows.GraphValidator

  @doc """
  Returns `{:ok, %{"nodes" => ..., "connections" => ..., "comments" => ...}}`, or
  `{:error, reason}` where `reason` is `:invalid_json`, `:not_a_flow` or a message
  of the validator.
  """
  def read(json, opts \\ []) when is_binary(json) do
    with {:ok, decoded} <- decode(json),
         {:ok, graph} <- graph(decoded),
         {:ok, definitions} <- definitions(opts),
         graph = clear_credentials(graph, definitions),
         :ok <- validate(graph, opts) do
      {:ok, normalize(graph)}
    end
  end

  defp decode(json) do
    case Jason.decode(json) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _reason} -> {:error, :invalid_json}
    end
  end

  defp graph(%{"data" => %{"nodes" => _nodes} = flow}), do: graph(flow)

  defp graph(%{"nodes" => nodes, "connections" => connections} = flow)
       when is_list(nodes) and is_list(connections) do
    {:ok,
     %{
       "nodes" => nodes,
       "connections" => connections,
       "comments" => Map.get(flow, "comments") || []
     }}
  end

  defp graph(_decoded), do: {:error, :not_a_flow}

  defp definitions(opts) do
    case GraphValidator.definitions(opts) do
      {:ok, definitions} -> {:ok, definitions}
      {:error, _field, message} -> {:error, message}
    end
  end

  defp clear_credentials(graph, definitions) do
    Map.update!(graph, "nodes", fn nodes ->
      Enum.map(nodes, &clear_node_credentials(&1, definitions))
    end)
  end

  defp clear_node_credentials(%{"type" => type, "controls" => %{} = controls} = node, definitions) do
    fields =
      for %{type: :credential, name: name} <- definition_fields(definitions[type]),
          do: to_string(name)

    %{node | "controls" => Map.new(controls, &clear_field(&1, fields))}
  end

  defp clear_node_credentials(node, _definitions), do: node

  defp definition_fields(%{ui_fields: fields}) when is_list(fields), do: fields
  defp definition_fields(_definition), do: []

  defp clear_field({key, _value} = field, fields) do
    if key in fields, do: {key, ""}, else: field
  end

  # As a saved flow has them, once the validator knows they are objects.
  defp normalize(graph) do
    %{
      graph
      | "nodes" => Graph.normalize_nodes(graph["nodes"]),
        "connections" => Graph.normalize_connections(graph["connections"])
    }
  end

  # The validator checks that each node is an object before it reads one.
  defp validate(graph, opts) do
    with :ok <- GraphValidator.validate(graph["nodes"], graph["connections"], opts),
         :ok <- GraphValidator.validate_comments(graph["comments"]) do
      :ok
    else
      {:error, _field, message} -> {:error, message}
    end
  end
end
