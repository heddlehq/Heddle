defmodule HeddleUI.Icons do
  @moduledoc """
  Every heroicon, outline and solid, for the stylesheet.

  Tailwind only makes the `hero-*` classes it finds in Heddle's code, but a node's
  icon may come from an integration package or from a manifest installed while
  Heddle runs. So `assets/css/icons.css` lists them all; `mix heddle.icons` writes it.
  """

  @doc "Where the list is written."
  def path, do: Path.expand("../../assets/css/icons.css", __DIR__)

  @doc "The list, as the CSS Tailwind reads."
  def css do
    names =
      Path.expand("../../priv/heroicons/24/outline/*.svg", __DIR__)
      |> Path.wildcard()
      |> Enum.map(&Path.basename(&1, ".svg"))
      |> Enum.sort()

    """
    /* Written by `mix heddle.icons`, see HeddleUI.Icons. */
    @source inline("hero-{#{Enum.join(names, ",")}}{,-solid}");
    """
  end
end
