defmodule HeddleNodes.Nodes.Wait do
  @moduledoc """
  Pauses the run for a while, until a date, or until its address is called.

  It only says how long. The runner stops there and hands back what is left of the
  run, the worker saves it, and a job picks it up again, so a wait survives a restart
  and holds no worker while it lasts. See `HeddleNodes.Runner`.
  """

  use Bobbin.Node

  alias HeddleNodes.Template

  @units %{
    "seconds" => 1,
    "minutes" => 60,
    "hours" => 3_600,
    "days" => 86_400
  }
  @longest_wait 366 * 86_400

  definition do
    %{
      name: "Wait",
      title: "Wait",
      category: :flow_control,
      color: "bg-amber-500/15 text-amber-700 dark:text-amber-300",
      description:
        "Pauses the run for a while, until a date, or until a call to {{resume_url}}. With a call, How long is the most it waits, and the run goes on through timeout after it.",
      icon: "hero-pause-circle-solid",
      inputs: [:exec],
      outputs: [:exec, "timeout"],
      show: true,
      ui_fields: [
        %{
          type: :select,
          name: :wait_for,
          label: "Wait",
          options: [
            %{label: "For a while", value: "time"},
            %{label: "Until a date", value: "date"},
            %{label: "Until a call", value: "call"}
          ],
          default: "time"
        },
        %{type: :text, name: :amount, label: "How long", default: "5"},
        %{
          type: :select,
          name: :unit,
          label: "Unit",
          options: Map.keys(@units) |> Enum.sort_by(&@units[&1]),
          default: "minutes"
        },
        %{type: :text, name: :wait_until, label: "Date (ISO 8601, UTC)", default: ""}
      ]
    }
  end

  @impl true
  def handler(context, _input) do
    case context["wait_for"] || "time" do
      "date" -> until_date(context)
      "call" -> until_call(context)
      _time -> for_a_while(context)
    end
  end

  defp for_a_while(context) do
    with {:ok, seconds} <- duration(context) do
      pause(%{"resume_at" => later(seconds)}, seconds, context)
    end
  end

  defp until_date(context) do
    text = context["wait_until"] |> Template.render(context) |> String.trim()

    with {:ok, at} <- parse_date(text) do
      seconds = DateTime.diff(at, DateTime.utc_now())

      if seconds > @longest_wait do
        {:error, "#{text} is more than a year away."}
      else
        pause(%{"resume_at" => DateTime.to_iso8601(at)}, seconds, context)
      end
    end
  end

  # An empty How long waits for the call for as long as it takes.
  defp until_call(context) do
    if blank?(context["amount"]) do
      {:wait, %{"call" => true}}
    else
      with {:ok, seconds} <- duration(context) do
        {:wait, %{"call" => true, "resume_at" => later(seconds)}}
      end
    end
  end

  # What is already due doesn't stop the run.
  defp pause(_wait, seconds, context) when seconds <= 0, do: {:ok, context}
  defp pause(wait, _seconds, _context), do: {:wait, wait}

  defp duration(context) do
    amount = context["amount"] |> Template.render(context) |> String.trim()
    unit = Map.get(@units, context["unit"], 60)

    case Float.parse(amount) do
      {number, ""} when number * unit > @longest_wait ->
        {:error, "A Wait can last a year at most."}

      {number, ""} when number >= 0 ->
        {:ok, round(number * unit)}

      _other ->
        {:error, "How long must be a number, like 5, and it is #{inspect(amount)}."}
    end
  end

  defp later(seconds) do
    DateTime.utc_now()
    |> DateTime.add(seconds)
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end

  defp parse_date(text) do
    case DateTime.from_iso8601(text) do
      {:ok, at, _offset} ->
        {:ok, at}

      {:error, _reason} ->
        case NaiveDateTime.from_iso8601(text) do
          {:ok, naive} ->
            {:ok, DateTime.from_naive!(naive, "Etc/UTC")}

          {:error, _reason} ->
            {:error, "The date must be like 2026-12-24T18:00:00Z, and it is #{inspect(text)}."}
        end
    end
  end

  defp blank?(value), do: not is_binary(value) or String.trim(value) == ""
end
