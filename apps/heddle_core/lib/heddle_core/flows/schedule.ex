defmodule HeddleCore.Flows.Schedule do
  @moduledoc """
  Reads the cron expression of a Schedule node.
  """

  alias Oban.Cron.Expression

  def valid?(cron), do: match?({:ok, _expression}, parse(cron))

  def due?(cron, datetime) do
    case parse(cron) do
      {:ok, expression} -> Expression.now?(expression, datetime)
      :error -> false
    end
  end

  # @reboot is always "now" to Oban, which would start the flow every minute.
  defp parse(cron) when is_binary(cron) do
    case Expression.parse(String.trim(cron)) do
      {:ok, %{reboot?: false} = expression} -> {:ok, expression}
      _other -> :error
    end
  end

  defp parse(_cron), do: :error
end
