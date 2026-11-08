defmodule HeddleUI.PublicAPI.V1.VersionJSON do
  @moduledoc """
  The versions of a workflow, see `HeddleCore.Flows.Versions`. A list says what each
  changed from the one before; a single version has its graph too.
  """

  alias Heddle.Graph
  alias Heddle.Graph.Diff
  alias Heddle.Graph.Layout
  alias HeddleCore.Flows.Version

  def index(%{entries: entries, published_id: published_id}) do
    %{data: Enum.map(entries, &entry(&1, published_id))}
  end

  def show(%{version: version, published_id: published_id}) do
    %{data: graph(version, published_id)}
  end

  @doc "A version with its graph."
  def graph(%Version{} = version, published_id) do
    version
    |> data(published_id)
    |> Map.merge(%{
      nodes: Layout.place(version.nodes, version.connections),
      connections: Graph.normalize_connections(version.connections),
      comments: version.comments
    })
  end

  @doc "A version of a list, with what it changed and who changed it."
  def entry(%{version: version, diff: diff, contributors: contributors}, published_id) do
    version
    |> data(published_id)
    |> Map.merge(%{
      changes: Diff.summary(diff),
      contributors: Enum.map(contributors, &person/1)
    })
  end

  defp data(%Version{} = version, published_id) do
    %{
      id: version.id,
      number: version.number,
      kind: version.kind,
      live: version.id == published_id,
      note: version.note,
      author: loaded_person(version.author),
      source_version_number: loaded_number(version.source),
      inserted_at: version.inserted_at
    }
  end

  defp loaded_person(%Ecto.Association.NotLoaded{}), do: nil
  defp loaded_person(nil), do: nil
  defp loaded_person(user), do: person(user)

  defp loaded_number(%Ecto.Association.NotLoaded{}), do: nil
  defp loaded_number(nil), do: nil
  defp loaded_number(version), do: version.number

  defp person(user), do: %{id: user.id, username: user.username, email: user.email}
end
