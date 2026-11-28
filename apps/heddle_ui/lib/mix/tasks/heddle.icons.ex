defmodule Mix.Tasks.Heddle.Icons do
  @shortdoc "Writes the list of heroicons the stylesheet carries"

  @moduledoc """
  Writes `assets/css/icons.css` in heddle_ui, see `HeddleUI.Icons`. Run it after
  updating heroicons. A test fails while the file is out of date.
  """

  use Mix.Task

  @impl true
  def run(_args) do
    File.write!(HeddleUI.Icons.path(), HeddleUI.Icons.css())
    Mix.shell().info("Wrote #{Path.relative_to_cwd(HeddleUI.Icons.path())}")
  end
end
