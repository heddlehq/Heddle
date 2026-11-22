defmodule HeddleUI.IconsTest do
  use ExUnit.Case, async: true

  test "the stylesheet lists every heroicon" do
    assert File.read!(HeddleUI.Icons.path()) == HeddleUI.Icons.css(),
           "Run `mix heddle.icons` and commit apps/heddle_ui/assets/css/icons.css"
  end
end
