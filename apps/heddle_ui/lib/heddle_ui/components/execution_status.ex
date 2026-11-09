defmodule HeddleUI.Components.ExecutionStatus do
  @moduledoc """
  How the status of a run shows: a badge with its name, or a dot beside it. Each
  status has an icon too, so it never reads by color alone.
  """
  use HeddleUI, :html

  attr :status, :string, required: true
  attr :class, :any, default: nil

  def status_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[11px] font-semibold uppercase tracking-wide",
      badge_classes(@status),
      @class
    ]}>
      <.icon name={status_icon(@status)} class={["size-3", @status == "running" && "animate-spin"]} />
      {label(@status)}
    </span>
    """
  end

  attr :status, :string, required: true
  attr :class, :any, default: nil

  def status_dot(assigns) do
    ~H"""
    <span
      class={["relative inline-flex size-2 shrink-0 rounded-full", dot_classes(@status), @class]}
      title={label(@status)}
    >
      <span
        :if={@status in ~w(running queued)}
        class={["absolute inset-0 animate-ping rounded-full opacity-60", dot_classes(@status)]}
      />
    </span>
    """
  end

  @doc "The name of `status`, in the language of the person reading it."
  def label("queued"), do: gettext("Queued")
  def label("running"), do: gettext("Running")
  def label("waiting"), do: gettext("Waiting")
  def label("succeeded"), do: gettext("Succeeded")
  def label("failed"), do: gettext("Failed")
  def label(other), do: other

  defp status_icon("succeeded"), do: "hero-check-micro"
  defp status_icon("failed"), do: "hero-x-mark-micro"
  defp status_icon("waiting"), do: "hero-pause-micro"
  defp status_icon("running"), do: "hero-arrow-path-micro"
  defp status_icon(_queued), do: "hero-clock-micro"

  defp badge_classes("succeeded"),
    do: "bg-emerald-100 text-emerald-800 dark:bg-emerald-950/60 dark:text-emerald-300"

  defp badge_classes("failed"),
    do: "bg-red-100 text-red-800 dark:bg-red-950/60 dark:text-red-300"

  defp badge_classes("waiting"),
    do: "bg-violet-100 text-violet-800 dark:bg-violet-950/60 dark:text-violet-300"

  defp badge_classes("running"),
    do: "bg-blue-100 text-blue-800 dark:bg-blue-950/60 dark:text-blue-300"

  defp badge_classes(_queued),
    do: "bg-amber-100 text-amber-800 dark:bg-amber-950/60 dark:text-amber-300"

  defp dot_classes("succeeded"), do: "bg-emerald-500"
  defp dot_classes("failed"), do: "bg-red-500"
  defp dot_classes("waiting"), do: "bg-violet-500"
  defp dot_classes("running"), do: "bg-blue-500"
  defp dot_classes(_queued), do: "bg-amber-500"
end
