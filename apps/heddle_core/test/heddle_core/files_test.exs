defmodule HeddleCore.FilesTest do
  # Changes the limits, which are global.
  use HeddleCore.DataCase, async: false

  alias HeddleCore.Files

  test "keeps a file and reads it back by its reference" do
    assert {:ok, %{"id" => id, "name" => "a.txt", "mime" => "text/plain", "size" => 5} = ref} =
             Files.store(["hel", "lo"], %{"name" => "a.txt", "mime" => "text/plain"})

    assert id =~ ~r/\A[0-9a-f]{32}\z/
    assert Files.read(ref) == {:ok, "hello"}
  end

  test "a file past the retention is deleted, and reading it says so" do
    {:ok, ref} = Files.store("old", %{"name" => "old.txt"})

    assert Files.prune(DateTime.add(DateTime.utc_now(), 6 * 86_400)) == 0
    assert Files.prune(DateTime.add(DateTime.utc_now(), 8 * 86_400)) == 1
    assert {:error, "The file is gone" <> _} = Files.read(ref)
  end

  test "refuses a file larger than a run may keep" do
    Application.put_env(:heddle_core, :files, max_bytes: 3)
    on_exit(fn -> Application.delete_env(:heddle_core, :files) end)

    assert {:error, message} = Files.store("four", %{})
    assert message =~ "more than"
  end
end
