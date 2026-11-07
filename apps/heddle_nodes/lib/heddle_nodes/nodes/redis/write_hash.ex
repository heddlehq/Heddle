defmodule HeddleNodes.Nodes.Redis.WriteHash do
  use Bobbin.Node

  alias HeddleNodes.Integration
  alias HeddleNodes.Services.Redis

  definition do
    Redis.definition(
      "Write Hash",
      "Saves fields in a hash, and leaves the others as they are.",
      [
        Redis.key_field(),
        %{type: :textarea, name: :fields, label: "Fields", default: "{{result}}"}
      ]
    )
  end

  @impl true
  def handler(context, _input) do
    Redis.run(context, fn conn ->
      with {:ok, key} <- Redis.key(context),
           {:ok, pairs} <- pairs(context),
           {:ok, added} <- Redis.command(conn, ["HSET", key | pairs]) do
        {:ok, %{"key" => key, "added" => added}}
      end
    end)
  end

  defp pairs(context) do
    case Integration.json(context, "fields") do
      {:ok, %{} = fields} when map_size(fields) > 0 ->
        {:ok, Enum.flat_map(fields, fn {field, value} -> [field, to_text(value)] end)}

      {:ok, _other} ->
        {:error, "Fields: give an object, from field to value."}

      {:error, message} ->
        {:error, message}
    end
  end

  defp to_text(value) when is_binary(value), do: value
  defp to_text(value) when is_map(value) or is_list(value), do: Jason.encode!(value)
  defp to_text(value), do: to_string(value)
end
