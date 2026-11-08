defmodule Heddle.Graph.Settings do
  @moduledoc """
  How a node behaves when it runs, apart from what it does: how often it tries again,
  what a failure does to the run, and the data pinned to it.

  It is stored in a node's optional `settings`, which only holds what differs from the
  defaults:

    * `"retries"`: how many more times a failing step runs before it fails, 0 to 10.
    * `"retry_delay"`: seconds before the first new try, 0 to 300.
    * `"retry_backoff"`: `"fixed"`, the same wait each time, or `"exponential"`, which
      doubles it after each try.
    * `"on_error"`: what a failure does once no try is left. `"stop"` sends it to the
      node's `error` output when something is connected there, and fails the run
      otherwise. `"continue"` goes on through the node's usual output, with the error
      as the `result`. `"output"` gives every node an `error` output to send it to.
    * `"pin"`: `%{"output" => name, "data" => map}`, what a run started from the editor
      takes from this node instead of running it: the output it leaves through and
      what it adds to the context. Other runs ignore it.

  Settings are not controls on purpose: controls are part of the context while the
  node runs, and these must not shadow what a person reads.
  """

  @on_error ~w(stop continue output)
  @backoffs ~w(fixed exponential)
  @keys ~w(retries retry_delay retry_backoff on_error pin)
  @max_retries 10
  @max_delay 300

  defstruct retries: 0, retry_delay: 0, retry_backoff: "fixed", on_error: "stop", pin: nil

  @doc "The values `on_error` takes."
  def on_error_values, do: @on_error

  @doc "Reads the stored settings of a node. What is missing or invalid takes its default."
  def new(settings) when is_map(settings) do
    %__MODULE__{
      retries: integer_in(settings["retries"], 0..@max_retries, 0),
      retry_delay: number_in(settings["retry_delay"], 0, @max_delay, 0),
      retry_backoff: one_of(settings["retry_backoff"], @backoffs, "fixed"),
      on_error: one_of(settings["on_error"], @on_error, "stop"),
      pin: pin(settings["pin"])
    }
  end

  def new(_settings), do: %__MODULE__{}

  @doc """
  Whether `settings`, as stored, holds only what a node takes. `nil` means none.
  """
  def valid?(nil), do: true

  def valid?(settings) when is_map(settings) do
    Enum.all?(Map.keys(settings), &(&1 in @keys)) and
      valid_value?(settings, "retries", &(is_integer(&1) and &1 in 0..@max_retries)) and
      valid_value?(settings, "retry_delay", &(is_number(&1) and &1 >= 0 and &1 <= @max_delay)) and
      valid_value?(settings, "retry_backoff", &(&1 in @backoffs)) and
      valid_value?(settings, "on_error", &(&1 in @on_error)) and
      valid_value?(settings, "pin", &(not is_nil(pin(&1))))
  end

  def valid?(_settings), do: false

  defp valid_value?(settings, key, check) do
    case Map.fetch(settings, key) do
      :error -> true
      {:ok, nil} -> true
      {:ok, value} -> check.(value)
    end
  end

  @doc "Whether the node has an `error` output because its settings give it one."
  def error_output?(%{"on_error" => "output"}), do: true
  def error_output?(%__MODULE__{on_error: "output"}), do: true
  def error_output?(_settings), do: false

  @doc """
  How long to wait, in ms, before try number `attempt`, the second being 2. It never
  waits more than #{@max_delay} seconds at once.
  """
  def delay(%__MODULE__{retry_delay: delay, retry_backoff: "exponential"}, attempt) do
    min(round(delay * 1000 * Integer.pow(2, max(attempt - 2, 0))), @max_delay * 1000)
  end

  def delay(%__MODULE__{retry_delay: delay}, _attempt), do: round(delay * 1000)

  defp pin(%{"output" => output, "data" => data}) when is_binary(output) and is_map(data) do
    %{"output" => output, "data" => data}
  end

  defp pin(_pin), do: nil

  defp integer_in(value, first..last//_, _default) when is_integer(value),
    do: value |> max(first) |> min(last)

  defp integer_in(_value, _range, default), do: default

  defp number_in(value, low, high, _default) when is_number(value),
    do: value |> max(low) |> min(high)

  defp number_in(_value, _low, _high, default), do: default

  defp one_of(value, values, default), do: if(value in values, do: value, else: default)
end
