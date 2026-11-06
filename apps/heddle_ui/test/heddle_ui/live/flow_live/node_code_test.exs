defmodule HeddleUI.FlowLive.NodeCodeTest do
  use ExUnit.Case, async: true

  alias HeddleUI.FlowLive.NodeCode

  describe "from_controls/1" do
    test "reads the code of each language" do
      assert NodeCode.from_controls(%{
               "language" => %{"value" => "python"},
               "code_elixir" => %{"value" => "1 + 1"},
               "code_python" => %{"value" => "print(1)"}
             }) == %{language: "python", code_elixir: "1 + 1", code_python: "print(1)"}
    end

    test "uses the older code field for the node's language when its own is blank" do
      controls = %{
        "language" => %{"value" => "python"},
        "code" => %{"value" => "print(1)"},
        "code_elixir" => %{"value" => ""},
        "code_python" => %{"value" => "  "}
      }

      assert NodeCode.from_controls(controls) ==
               %{language: "python", code_elixir: "", code_python: "print(1)"}
    end

    test "prefers the language's own code over the older field" do
      controls = %{"code" => %{"value" => "old"}, "code_elixir" => %{"value" => "new"}}

      assert %{code_elixir: "new"} = NodeCode.from_controls(controls)
    end

    test "defaults to Elixir with no code" do
      assert NodeCode.from_controls(%{}) ==
               %{language: "elixir", code_elixir: "", code_python: ""}
    end
  end

  describe "current/1" do
    test "returns the code of the selected language" do
      code = %{language: "python", code_elixir: "1 + 1", code_python: "print(1)"}

      assert NodeCode.current(code) == "print(1)"
      assert NodeCode.current(%{code | language: "elixir"}) == "1 + 1"
    end
  end
end
