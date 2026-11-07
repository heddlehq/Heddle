defmodule Heddle.Graph.Node do
  @moduledoc """
  A step of a flow, without what only matters to draw it.
  """

  @enforce_keys [:id, :type]
  defstruct [:id, :type, :label, controls: %{}]

  @doc "Builds a node from its stored form."
  def new(%{} = node) do
    %__MODULE__{
      id: to_string(node["id"]),
      type: node["type"],
      label: node["label"],
      controls: node["controls"] || %{}
    }
  end
end
