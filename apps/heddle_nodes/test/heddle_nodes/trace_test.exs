defmodule HeddleNodes.TraceTest do
  use ExUnit.Case, async: true

  alias HeddleNodes.Trace

  describe "step/2" do
    setup do
      Trace.start()
      :ok
    end

    test "keeps the context a step got and what it changed" do
      before = %{"name" => "Ana", "result" => 1, "gone" => true}
      after_step = %{"name" => "Ana", "result" => 2, "new" => "x"}

      assert Trace.step(before, after_step) == %{
               "input" => before,
               "output" => %{"result" => 2, "new" => "x"},
               "removed" => ["gone"]
             }
    end

    test "stops keeping data after 500 steps" do
      for _step <- 1..500, do: Trace.step(%{}, %{})

      assert Trace.step(%{}, %{}) == %{"omitted" => true}
    end

    test "says when it cut something" do
      assert %{"truncated" => true} = Trace.step(%{"text" => String.duplicate("a", 3000)}, %{})
    end
  end

  describe "snapshot/1" do
    test "leaves small JSON as it is" do
      value = %{"a" => [1, 2.5, "x", nil, true], "b" => %{"c" => "d"}}
      assert Trace.snapshot(value) == {value, false}
    end

    test "cuts long texts and lists, and shows only the size of a file" do
      {value, true} =
        Trace.snapshot(%{
          "text" => String.duplicate("a", 2500),
          "list" => Enum.to_list(1..150),
          "file" => %{"encoding" => "base64", "content" => String.duplicate("A", 4000)}
        })

      assert String.length(value["text"]) == 2001
      assert length(value["list"]) == 101
      assert List.last(value["list"]) == "… 50 more"
      assert value["file"] == %{"encoding" => "base64", "size" => 3000}
    end

    test "turns what isn't JSON into text" do
      {value, true} =
        Trace.snapshot(%{"pid" => self(), "bytes" => <<255, 0>>, "tuple" => {:a, 1}})

      assert value["pid"] =~ "#PID"
      assert value["bytes"] == "<2 bytes>"
      assert value["tuple"] == ["a", 1]
    end

    test "stops after a number of values, whatever the shape" do
      wide = Map.new(1..100, &{"k#{&1}", Enum.to_list(1..100)})

      {value, true} = Trace.snapshot(wide)
      assert value |> Jason.encode!() |> byte_size() < 40_000
    end
  end
end
