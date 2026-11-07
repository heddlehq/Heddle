defmodule HeddleUI.Agent.Transcript do
  @moduledoc """
  What a conversation looks like, built from its events.

  This is the protocol of the agent. The session keeps one of these, each client keeps
  its own from the same events, and all of it is plain JSON:

    * `user_message` - `text`
    * `text_delta` - `text`, part of a reply
    * `tool_started` - `id`, `name`, `args`
    * `tool_finished` - `id`, `ok`, `output`
    * `failed` - `message`
    * `status` - `status`, `"running"` or `"idle"`
    * `permission` - `permission`, what is waiting for an answer, or nil
    * `reset` - `items`, another conversation took the place of this one
  """

  def new, do: %{items: [], status: "idle", permission: nil}

  def reduce(_transcript, %{type: "reset", items: items}) do
    %{new() | items: items}
  end

  def reduce(transcript, %{type: "user_message", text: text}) do
    push(transcript, %{role: "user", text: text})
  end

  def reduce(transcript, %{type: "text_delta", text: text}) do
    case List.last(transcript.items) do
      %{role: "assistant"} = last ->
        replace_last(transcript, %{last | text: last.text <> text})

      _other ->
        push(transcript, %{role: "assistant", text: text})
    end
  end

  def reduce(transcript, %{type: "tool_started", id: id, name: name, args: args}) do
    item = %{id: id, role: "tool", name: name, args: args, status: "running", output: nil}
    %{transcript | items: transcript.items ++ [item]}
  end

  def reduce(transcript, %{type: "tool_finished", id: id, ok: ok, output: output}) do
    items =
      Enum.map(transcript.items, fn
        %{id: ^id, role: "tool"} = item ->
          %{item | status: if(ok, do: "ok", else: "error"), output: output}

        item ->
          item
      end)

    %{transcript | items: items}
  end

  def reduce(transcript, %{type: "failed", message: message}) do
    push(transcript, %{role: "error", text: message})
  end

  def reduce(transcript, %{type: "status", status: status}) do
    %{transcript | status: status, items: settle(transcript.items, status)}
  end

  def reduce(transcript, %{type: "permission", permission: permission}) do
    %{transcript | permission: permission}
  end

  @doc "Reads an item back from where it was saved, which only keeps strings as keys."
  def item_from_saved(item) do
    Map.new(item, fn {key, value} -> {saved_key(key), value} end)
  end

  defp saved_key(key) when key in ~w(id role text name args status output) do
    String.to_existing_atom(key)
  end

  # A tool that was cut off by a stop will never report back.
  defp settle(items, "idle") do
    Enum.map(items, fn
      %{role: "tool", status: "running"} = item -> %{item | status: "error"}
      item -> item
    end)
  end

  defp settle(items, _status), do: items

  defp push(transcript, item) do
    id = "item-#{length(transcript.items) + 1}"
    %{transcript | items: transcript.items ++ [Map.put(item, :id, id)]}
  end

  defp replace_last(transcript, item) do
    %{transcript | items: List.replace_at(transcript.items, -1, item)}
  end
end
