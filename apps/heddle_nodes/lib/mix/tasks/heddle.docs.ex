defmodule Mix.Tasks.Heddle.Docs do
  @shortdoc "Writes the reference of the nodes for the documentation site"

  @moduledoc """
  Writes `docs/reference/nodes.json` from the definitions of the nodes and from
  `docs/nodes/`, see `HeddleNodes.Docs`.

      mix heddle.docs

  Run it after changing a node. A test fails while the file is out of date.
  """

  use Mix.Task

  @impl true
  def run(_args) do
    Mix.Task.run("compile")

    %{missing: missing, unknown: unknown} = HeddleNodes.Docs.coverage()

    if missing != [] do
      Mix.shell().info("Nodes with no entry in docs/nodes/: " <> Enum.join(missing, ", "))
    end

    if unknown != [] do
      Mix.shell().info("Entries in docs/nodes/ for no node: " <> Enum.join(unknown, ", "))
    end

    path = HeddleNodes.Docs.reference_path()
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, HeddleNodes.Docs.encode())
    Mix.shell().info("Wrote #{Path.relative_to_cwd(path)}")
  end
end
