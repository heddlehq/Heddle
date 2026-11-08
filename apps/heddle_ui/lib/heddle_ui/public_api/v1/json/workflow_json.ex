defmodule HeddleUI.PublicAPI.V1.WorkflowJSON do
  alias Heddle.Graph
  alias Heddle.Graph.Layout
  alias HeddleCore.Flows.Flow

  def index(%{workflows: workflows, meta: meta}) do
    %{data: Enum.map(workflows, &data/1), meta: meta}
  end

  def show(%{workflow: workflow}) do
    %{data: data(workflow)}
  end

  defp data(%Flow{} = workflow) do
    %{
      id: workflow.id,
      name: workflow.name,
      # A flow can be saved without positions, and every client has to draw it.
      nodes: Layout.place(workflow.nodes, workflow.connections),
      connections: Graph.normalize_connections(workflow.connections),
      comments: workflow.comments,
      # The graph above is the draft. Production runs this version, and a workflow
      # without one isn't in production yet.
      published_version_id: workflow.published_version_id,
      inserted_at: workflow.inserted_at,
      updated_at: workflow.updated_at
    }
  end
end
