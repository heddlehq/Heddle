defmodule HeddleUI.AIChat do
  @moduledoc """
  Shared helpers for the AI chat experiences (`FlowLive` and `FlowAiCreatorLive`).

  Centralizes the logic that used to be duplicated across both LiveViews:

    * converting the in-memory `{:user | :ai, text}` message list into the
      `%{role: ..., content: ...}` shape the agents expect;
    * consuming an agent stream while forwarding chunks/errors to the LiveView;
    * appending a streamed chunk to the running assistant message;
    * extracting the `create_flow` JSON out of an assistant reply;
    * reading the planner's plan marker and hiding it from the user; and
    * normalizing the AI-generated nodes into the form a flow is stored in.
  """

  alias HeddleCore.Flows.GraphValidator

  @plan_marker ~r/\[?PLAN_PROPOSED\]?/i
  @partial_marker ~r/\[[A-Z_]*\z/
  @bold ~r/\*\*(.+?)\*\*/

  @doc """
  Converts the chat message list into the agent message format.

  Drops the trailing element, which is always the empty `{:ai, ""}` placeholder
  appended right before a request is sent.
  """
  def to_api_messages(messages) do
    messages
    |> Enum.map(fn
      {:user, text} -> %{role: "user", content: text}
      {:ai, text} -> %{role: "assistant", content: text}
    end)
    |> List.delete_at(-1)
  end

  @doc """
  Consumes an agent stream, forwarding events to `parent`.

  Sends `{:chat_stream_chunk, text}` for each text delta and
  `{:chat_stream_error, reason}` on error. Returns the fully accumulated reply
  as a binary, or `{:error, reason}` if the stream errored.
  """
  def consume_stream(stream, parent) do
    Enum.reduce_while(stream, "", fn
      {:text_delta, text}, acc ->
        send(parent, {:chat_stream_chunk, text})
        {:cont, acc <> text}

      {:error, reason}, _acc ->
        send(parent, {:chat_stream_error, reason})
        {:halt, {:error, reason}}

      {:finish, _reason}, acc ->
        {:cont, acc}

      _other, acc ->
        {:cont, acc}
    end)
  end

  @doc """
  Appends a streamed `chunk` to the last assistant message, if there is one.
  """
  def append_chunk(messages, chunk) do
    case List.last(messages) do
      {:ai, last_content} -> List.replace_at(messages, -1, {:ai, last_content <> chunk})
      _ -> messages
    end
  end

  @doc """
  Returns the map of node definitions (`name => definition`) used by the canvas
  when loading graph data.
  """
  def node_definitions do
    HeddleNodes.Nodes.all_nodes()
    |> Map.new(fn node -> {node.name, node} end)
  end

  @doc """
  Tells whether an assistant reply proposes a plan the user can approve.

  The planner signals it by ending the reply with the `[PLAN_PROPOSED]` marker.
  """
  def plan_proposed?(content) when is_binary(content) do
    Regex.match?(@plan_marker, content)
  end

  @doc """
  Returns the text of an assistant reply as the user should see it.

  Removes the plan marker, including the start of it while it is still streaming.
  Replies render as plain text, so it also drops the Markdown bold the model uses.
  The stored message keeps the marker, so the model still sees it in the history.
  """
  def display_text(content) when is_binary(content) do
    content
    |> String.replace(@plan_marker, "")
    |> String.replace(@partial_marker, "")
    |> String.replace(@bold, "\\1")
    |> String.trim_trailing()
  end

  @doc """
  Tells whether an assistant reply is flow JSON, even a partial one still streaming.
  """
  def flow_json?(content) when is_binary(content) do
    trimmed = String.trim_leading(content)

    String.starts_with?(trimmed, ["{", "```"]) or String.contains?(content, ~s("create_flow"))
  end

  @doc """
  Extracts a `create_flow` payload from an assistant reply.

  Handles both a reply that is pure JSON (optionally fenced with ```json) and a
  reply where the JSON is embedded in surrounding prose. Returns `{:ok, json}`
  only when the decoded payload is a `create_flow` action, otherwise `:error`.
  """
  def extract_create_flow_json(content) when is_binary(content) do
    case decode_create_flow(strip_code_fence(content)) do
      {:ok, json} ->
        {:ok, json}

      :error ->
        case Regex.run(~r/\{[\s\S]*"action":\s*"create_flow"[\s\S]*\}/m, content) do
          [candidate] -> decode_create_flow(candidate)
          _ -> :error
        end
    end
  end

  @doc """
  Normalizes AI-generated nodes into the form a flow is stored in.

  Flattens `{value: ...}` controls, applies the `Evaluate Code` and `Output` control
  defaults, and fills in `id/type/label`. A position from the model is left out: where
  a node goes is up to `Heddle.Graph.Layout`.
  """
  def normalize_nodes(raw_nodes) when is_list(raw_nodes) do
    Enum.map(raw_nodes, &normalize_node/1)
  end

  @doc """
  Reduces nodes to the fields a saved flow may have, which
  `HeddleCore.Flows.GraphValidator` requires.
  """
  def persistable_nodes(nodes) when is_list(nodes) do
    Enum.map(nodes, &Map.take(&1, GraphValidator.node_keys()))
  end

  defp normalize_node(node) do
    data = node["data"] || %{}
    name = node["name"]
    type = node["type"] || name
    label = node["label"] || data["label"] || name

    controls =
      node
      |> base_controls(data)
      |> flatten_control_values()
      |> normalize_controls_for(type, name)

    %{
      "id" => node["id"],
      "type" => type,
      "label" => label,
      "controls" => controls
    }
  end

  defp base_controls(node, data) do
    cond do
      is_map(node["controls"]) and node["controls"] != %{} -> node["controls"]
      is_map(data["controls"]) and data["controls"] != %{} -> data["controls"]
      true -> Map.drop(data, ["label", "x", "y", "controls"])
    end
  end

  defp flatten_control_values(controls) do
    Map.new(controls, fn {key, value} ->
      if is_map(value) and Map.has_key?(value, "value") do
        {key, value["value"]}
      else
        {key, value}
      end
    end)
  end

  defp normalize_controls_for(controls, type, name) do
    cond do
      "Evaluate Code" in [type, name] ->
        code_value = controls["code"] || controls["code_elixir"] || ""

        controls
        |> Map.put("code_elixir", code_value)
        |> Map.put_new("code_python", "")
        |> Map.put_new("language", "elixir")
        |> Map.delete("code")

      "Output" in [type, name] ->
        Map.put_new(controls, "status", "success")

      true ->
        controls
    end
  end

  defp strip_code_fence(content) do
    content
    |> String.replace(~r/^```json\s*/, "")
    |> String.replace(~r/\s*```$/, "")
    |> String.trim()
  end

  defp decode_create_flow(string) do
    case Jason.decode(string) do
      {:ok, %{"action" => "create_flow"} = json} -> {:ok, json}
      _ -> :error
    end
  end
end
