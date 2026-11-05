defmodule HeddleLocalTest do
  use ExUnit.Case, async: true

  @moduletag :tmp_dir

  describe "default_home/2" do
    test "uses LOCALAPPDATA on Windows" do
      assert HeddleLocal.default_home({:win32, :nt}, "C:/Users/ana/AppData/Local") ==
               "C:/Users/ana/AppData/Local/Heddle"
    end

    test "uses a dot directory elsewhere" do
      assert HeddleLocal.default_home({:unix, :linux}, nil) ==
               Path.join(System.user_home!(), ".heddle")
    end
  end

  describe "python_env/1" do
    test "keeps every cache inside the install folder" do
      for {_name, path} <- HeddleLocal.python_env("/home/ana/.heddle") do
        assert String.starts_with?(path, "/home/ana/.heddle/cache/")
      end
    end
  end

  describe "read_or_create/2" do
    test "creates the value once and keeps it", %{tmp_dir: dir} do
      path = Path.join(dir, "secret")

      assert HeddleLocal.read_or_create(path, fn -> "first" end) == "first"
      assert HeddleLocal.read_or_create(path, fn -> "second" end) == "first"
    end

    test "keeps the file private", %{tmp_dir: dir} do
      path = Path.join(dir, "secret")
      HeddleLocal.read_or_create(path, fn -> "value" end)

      assert Bitwise.band(File.stat!(path).mode, 0o077) == 0
    end

    test "replaces an empty file", %{tmp_dir: dir} do
      path = Path.join(dir, "secret")
      File.write!(path, "")

      assert HeddleLocal.read_or_create(path, fn -> "value" end) == "value"
    end
  end

  describe "free_port/2" do
    test "skips a port already in use" do
      {:ok, socket} = :gen_tcp.listen(0, ip: {127, 0, 0, 1})
      {:ok, taken} = :inet.port(socket)

      assert HeddleLocal.free_port(taken) > taken

      :gen_tcp.close(socket)
    end
  end
end
