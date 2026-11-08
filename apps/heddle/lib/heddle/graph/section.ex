defmodule Heddle.Graph.Section do
  @moduledoc """
  A part of a flow, drawn around its nodes on the canvas.

  The canvas keeps `nodes` up to date from where things are, so running never reads a
  position. The nodes of a section inside another are in both. A `manual` section
  doesn't run with the rest of the flow: only when it is run on its own.

  `nodes` is in the order its entry nodes run: top to bottom on the canvas.
  """

  @enforce_keys [:id]
  defstruct [:id, name: "", manual: false, nodes: []]

  @doc "Reads the sections among the comments of a flow."
  def list(comments) do
    for %{"kind" => "section"} = comment <- List.wrap(comments), do: new(comment)
  end

  defp new(comment) do
    %__MODULE__{
      id: to_string(comment["id"]),
      name: comment["text"] || "",
      manual: comment["manual"] == true,
      nodes: comment |> Map.get("nodes") |> List.wrap() |> Enum.map(&to_string/1)
    }
  end
end
