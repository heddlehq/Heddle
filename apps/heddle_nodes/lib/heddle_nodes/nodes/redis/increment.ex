defmodule HeddleNodes.Nodes.Redis.Increment do
  use Bobbin.Node

  alias HeddleNodes.Integration
  alias HeddleNodes.Services.Redis

  definition do
    Redis.definition(
      "Increment",
      "Adds to the number in a key, which starts at 0, and returns the new number.",
      [Redis.key_field(), %{type: :text, name: :amount, label: "Amount", default: "1"}]
    )
  end

  @impl true
  def handler(context, _input) do
    Redis.run(context, fn conn ->
      with {:ok, key} <- Redis.key(context),
           {:ok, amount} <- amount(context),
           {:ok, value} <- Redis.command(conn, ["INCRBY", key, amount]) do
        {:ok, %{"key" => key, "value" => value}}
      end
    end)
  end

  defp amount(context) do
    case String.trim(Integration.field(context, "amount")) do
      "" -> {:ok, 1}
      amount -> parse(amount)
    end
  end

  defp parse(amount) do
    case Integer.parse(amount) do
      {amount, ""} -> {:ok, amount}
      _other -> {:error, "Amount has to be a whole number."}
    end
  end
end
