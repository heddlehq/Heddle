defmodule HeddleUI.MCP.Tool do
  @moduledoc """
  Helpers shared by the MCP tools.
  """

  alias Anubis.Server.Response
  alias HeddleCore.ApiKeys.ApiKey
  alias HeddleCore.Flows

  @forbidden "Your role in this workspace doesn't allow this. Ask one of its admins."

  @doc """
  Runs `fun` with the caller's scope if its API key has `api_scope`.
  """
  def authorize(frame, api_scope, fun) do
    if ApiKey.allows?(frame.assigns.api_key, api_scope) do
      fun.(frame.assigns.current_scope)
    else
      error("This API key is missing the #{api_scope} scope.", frame)
    end
  end

  @doc "The error for something the caller's role doesn't allow."
  def forbidden(frame), do: error(@forbidden, frame)

  @doc """
  Runs `fun` with a flow the caller can see.
  """
  def with_flow(scope, id, frame, fun) do
    case Flows.get_flow(scope, id) do
      nil -> error("Flow #{id} was not found.", frame)
      flow -> fun.(flow)
    end
  end

  def reply(data, frame), do: {:reply, Response.json(Response.tool(), data), frame}

  def reply_text(text, frame), do: {:reply, Response.text(Response.tool(), text), frame}

  def error(message, frame), do: {:reply, Response.error(Response.tool(), message), frame}

  @doc "Runs only the section in `:section_id`, when there is one. See `Heddle.Graph.Section`."
  def put_section(input, %{section_id: id}) when is_binary(id) and id != "",
    do: Map.put(input, "section_id", id)

  def put_section(input, _params), do: input

  def changeset_error(:forbidden, frame), do: error(@forbidden, frame)
  def changeset_error(:not_found, frame), do: error("That flow was not found.", frame)

  def changeset_error(%Ecto.Changeset{} = changeset, frame) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, _opts} -> message end)
    |> Enum.map_join("; ", fn {field, messages} ->
      "#{field}: #{Enum.join(List.wrap(messages), ", ")}"
    end)
    |> error(frame)
  end
end
