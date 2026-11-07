defmodule HeddleUI.Components.ResultFileTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias HeddleUI.Components.ResultFile

  @image %{"content" => "iVBORw0KGgo=", "encoding" => "base64", "type" => "image/png"}

  defp render_file(value) do
    render_component(&ResultFile.result_file/1, id: "file", value: value)
  end

  describe "result_file/1" do
    test "shows an image, on its own or in a run's result" do
      assert render_file(@image) =~ ~s(src="data:image/png;base64,iVBORw0KGgo=")
      assert render_file(%{"result" => @image}) =~ "<img"
    end

    test "plays audio" do
      assert render_file(%{@image | "type" => "audio/mpeg"}) =~ "<audio"
    end

    test "shows nothing for what a browser shouldn't open" do
      refute render_file(%{@image | "type" => "image/svg+xml"}) =~ "<img"
      refute render_file(%{@image | "type" => "text/html"}) =~ "data:"
    end

    test "shows nothing for other results" do
      for value <- [nil, "text", %{"a" => 1}, [1, 2]] do
        refute render_file(value) =~ "<img"
      end
    end
  end

  describe "shorten/1" do
    test "hides the base64 wherever the file is, keeping everything else" do
      value = %{"result" => [@image], "name" => "x"}

      assert %{"result" => [file], "name" => "x"} = ResultFile.shorten(value)
      assert file["type"] == "image/png"
      refute file["content"] =~ "iVBOR"
    end

    test "leaves text alone" do
      value = %{"content" => "hello"}

      assert ResultFile.shorten(value) == value
    end
  end
end
