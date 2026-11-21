defmodule HeddleNodes.Nodes.Approval do
  @moduledoc """
  Pauses the run until a person approves or rejects it.

  It waits as a `Wait` waits for a call, so the run is saved and holds no worker. A
  person decides on the Approvals page, or anything calls `{{resume_url}}` with a
  `decision`, like a button in a Slack message or a link in an email. The runner then
  goes on through `approved` or `rejected`, see `decision/1`, and through `timeout` when
  How long passes first.
  """

  use Bobbin.Node

  alias HeddleNodes.Template

  @units %{
    "minutes" => 60,
    "hours" => 3_600,
    "days" => 86_400
  }
  @longest_wait 366 * 86_400

  @approved ~w(approve approved yes true 1)

  # A node's controls shadow the run while it executes, so these don't take names a
  # flow's own data would have, like `amount` or `title`.

  definition do
    %{
      name: "Approval",
      title: "Approval",
      category: :flow_control,
      color: "bg-amber-500/15 text-amber-700 dark:text-amber-300",
      description:
        "Pauses the run until a person approves or rejects it, on the Approvals page or through {{resume_url}} with a decision. Goes on through approved or rejected, or through timeout after How long.",
      icon: "hero-hand-raised-solid",
      inputs: [:exec],
      outputs: ["approved", "rejected", "timeout"],
      show: true,
      ui_fields: [
        %{type: :text, name: :approval_title, label: "What to approve", default: ""},
        %{type: :textarea, name: :approval_details, label: "Details", default: ""},
        %{type: :text, name: :approval_wait, label: "How long, blank for no limit", default: ""},
        %{
          type: :select,
          name: :approval_unit,
          label: "Unit",
          options: Map.keys(@units) |> Enum.sort_by(&@units[&1]),
          default: "days"
        }
      ]
    }
  end

  @impl true
  def handler(context, _input) do
    title = render(context, "approval_title")

    approval = %{
      "title" => if(title == "", do: "Approve this run?", else: title),
      "details" => render(context, "approval_details")
    }

    with {:ok, limit} <- limit(context) do
      {:wait, Map.merge(%{"call" => true, "approval" => approval}, limit)}
    end
  end

  @doc """
  Reads what a call decided: `"approved"` for `approve`, `approved`, `yes`, `true` or
  `1`, in its `decision`, and `"rejected"` for anything else, so a malformed call never
  approves.
  """
  def decision(request) when is_map(request) do
    given =
      request["decision"] || get_in(request, ["body", "decision"]) ||
        get_in(request, ["query_params", "decision"])

    normalized = given |> to_string() |> String.trim() |> String.downcase()

    if normalized in @approved, do: "approved", else: "rejected"
  end

  def decision(_request), do: "rejected"

  @doc """
  What the node leaves as its `result` once decided: the `decision`, who made it on
  the Approvals page, and their `comment`.
  """
  def result(request) when is_map(request) do
    %{
      "decision" => decision(request),
      # Only a decision on the Approvals page says who, since anyone with the address
      # could claim a name in a call.
      "by" => request["by"],
      "comment" =>
        request["comment"] || get_in(request, ["body", "comment"]) ||
          get_in(request, ["query_params", "comment"])
    }
  end

  def result(_request), do: %{"decision" => "rejected", "by" => nil, "comment" => nil}

  defp limit(context) do
    amount = render(context, "approval_wait")
    unit = Map.get(@units, context["approval_unit"], 86_400)

    case Float.parse(amount) do
      _blank when amount == "" ->
        {:ok, %{}}

      {number, ""} when number * unit > @longest_wait ->
        {:error, "An Approval can wait a year at most."}

      {number, ""} when number > 0 ->
        at =
          DateTime.utc_now()
          |> DateTime.add(round(number * unit))
          |> DateTime.truncate(:second)
          |> DateTime.to_iso8601()

        {:ok, %{"resume_at" => at}}

      _other ->
        {:error, "How long must be a number above 0, like 2, and it is #{inspect(amount)}."}
    end
  end

  defp render(context, key) do
    (context[key] || "") |> to_string() |> Template.render(context) |> String.trim()
  end
end
