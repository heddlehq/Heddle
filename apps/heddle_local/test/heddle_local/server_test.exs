defmodule HeddleLocal.ServerTest do
  use ExUnit.Case, async: true

  alias HeddleLocal.Server

  describe "browser_command/2" do
    test "passes an empty title to start on Windows, which reads the first quoted arg as one" do
      assert Server.browser_command({:win32, :nt}, "http://localhost:4000") ==
               {"cmd", ["/c", "start", "", "http://localhost:4000"]}
    end

    test "uses open on macOS" do
      assert Server.browser_command({:unix, :darwin}, "http://localhost:4000") ==
               {"open", ["http://localhost:4000"]}
    end
  end
end
