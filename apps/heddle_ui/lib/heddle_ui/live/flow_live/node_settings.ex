defmodule HeddleUI.FlowLive.NodeSettings do
  @moduledoc """
  The settings of a node, see `Heddle.Graph.Settings`, as the node drawer shows and
  sends them.

  A node keeps only what differs from the defaults, so a flow nobody tuned stays as
  it was.
  """

  alias Heddle.Graph.Settings

  @doc """
  Reads the `settings` fields of the drawer.

  Returns `{:ok, settings}`, or `{:error, :invalid_pin}` when the pinned data isn't a
  JSON object.
  """
  def from_params(params) when is_map(params) do
    with {:ok, pin} <- pin(params) do
      settings =
        %{
          "retries" => integer(params["retries"]),
          "retry_delay" => number(params["retry_delay"]),
          "retry_backoff" => params["retry_backoff"],
          "on_error" => params["on_error"],
          "pin" => pin
        }
        |> Settings.new()
        |> stored()

      {:ok, settings}
    end
  end

  def from_params(_params), do: {:ok, %{}}

  @doc "The values the drawer shows for `settings`, as stored on the canvas."
  def values(settings) do
    settings = Settings.new(settings)

    %{
      "retries" => settings.retries,
      "retry_delay" => settings.retry_delay,
      "retry_backoff" => settings.retry_backoff,
      "on_error" => settings.on_error,
      "pin" => settings.pin,
      "pin_data" => settings.pin && Jason.encode!(settings.pin["data"], pretty: true)
    }
  end

  @doc "Whether the definition of `type` gives the node an `error` output of its own."
  def own_error_output?(type) do
    case HeddleNodes.Nodes.get_node(type) do
      nil -> false
      definition -> "error" in Enum.map(definition[:outputs] || [], &to_string/1)
    end
  end

  # Only what isn't the default.
  defp stored(%Settings{} = settings) do
    defaults = %Settings{}

    %{
      "retries" => settings.retries,
      "retry_delay" => settings.retry_delay,
      "retry_backoff" => settings.retry_backoff,
      "on_error" => settings.on_error,
      "pin" => settings.pin
    }
    |> Map.reject(fn {key, value} ->
      value == Map.fetch!(defaults, String.to_existing_atom(key))
    end)
  end

  defp pin(%{"unpin" => "true"}), do: {:ok, nil}

  defp pin(%{"pin_data" => json, "pin_output" => output}) when is_binary(json) and output != "" do
    case Jason.decode(json) do
      {:ok, %{} = data} -> {:ok, %{"output" => output, "data" => data}}
      _not_an_object -> {:error, :invalid_pin}
    end
  end

  defp pin(_params), do: {:ok, nil}

  defp integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {number, ""} -> number
      _invalid -> nil
    end
  end

  defp integer(value) when is_integer(value), do: value
  defp integer(_value), do: nil

  defp number(value) when is_binary(value) do
    case Float.parse(String.trim(value)) do
      {number, ""} -> if number == trunc(number), do: trunc(number), else: number
      _invalid -> nil
    end
  end

  defp number(value) when is_number(value), do: value
  defp number(_value), do: nil
end
