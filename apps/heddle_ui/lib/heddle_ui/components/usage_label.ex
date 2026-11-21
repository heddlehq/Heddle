defmodule HeddleUI.Components.UsageLabel do
  @moduledoc """
  Words for what model calls cost, from a `"usage"` of `HeddleNodes.Usage`: its price
  when the model's is known, else its tokens.
  """

  use Gettext, backend: HeddleUI.Gettext

  @doc "Like `$0.0031`, or `1.2k tokens` when the price isn't known."
  def short(%{"cost" => cost}) when is_number(cost), do: money(cost)
  def short(usage), do: gettext("%{tokens} tokens", tokens: count(tokens(usage)))

  @doc "Every number, for a tooltip."
  def detail(usage) do
    parts = [
      ngettext("1 model call", "%{count} model calls", usage["calls"] || 0),
      gettext("%{tokens} tokens in", tokens: count(usage["input_tokens"] || 0)),
      gettext("%{tokens} tokens out", tokens: count(usage["output_tokens"] || 0))
    ]

    parts = if is_number(usage["cost"]), do: parts ++ [money(usage["cost"])], else: parts
    Enum.join(parts, " · ")
  end

  defp tokens(usage), do: (usage["input_tokens"] || 0) + (usage["output_tokens"] || 0)

  # A run of a few calls costs fractions of a cent, so small amounts keep their digits.
  defp money(cost) when cost == 0, do: "$0"
  defp money(cost) when cost < 0.01, do: "$" <> :erlang.float_to_binary(cost * 1.0, decimals: 4)
  defp money(cost), do: "$" <> :erlang.float_to_binary(cost * 1.0, decimals: 2)

  defp count(n) when n >= 1_000_000, do: "#{Float.round(n / 1_000_000, 1)}M"
  defp count(n) when n >= 1_000, do: "#{Float.round(n / 1_000, 1)}k"
  defp count(n), do: to_string(n)
end
