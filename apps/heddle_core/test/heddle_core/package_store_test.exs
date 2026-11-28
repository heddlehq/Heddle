defmodule HeddleCore.PackageStoreTest do
  use HeddleCore.DataCase, async: true

  import HeddleCore.FlowsFixtures

  alias HeddleCore.Executions
  alias HeddleCore.PackageStore

  setup do
    flow = flow_fixture()
    %{workspace_id: flow.workspace_id, flow: flow}
  end

  describe "records" do
    test "keeps any JSON value and counts its versions", %{workspace_id: ws} do
      assert {:error, :not_found} = PackageStore.get(ws, "jido", "a")

      assert {:ok, 1} = PackageStore.put(ws, "jido", "a", %{"stage" => "new"})
      assert {:ok, 2} = PackageStore.put(ws, "jido", "a", [1, 2])
      assert {:ok, %{key: "a", value: [1, 2], version: 2}} = PackageStore.get(ws, "jido", "a")

      assert {:ok, 3} = PackageStore.put(ws, "jido", "a", "text")
      assert {:ok, %{value: "text"}} = PackageStore.get(ws, "jido", "a")
    end

    test "keeps each namespace and workspace apart", %{workspace_id: ws} do
      other = flow_fixture().workspace_id
      {:ok, 1} = PackageStore.put(ws, "jido", "a", 1)

      assert {:error, :not_found} = PackageStore.get(ws, "other", "a")
      assert {:error, :not_found} = PackageStore.get(other, "jido", "a")
    end

    test "a version that isn't the record's is a conflict", %{workspace_id: ws} do
      assert {:ok, 1} = PackageStore.put(ws, "jido", "a", 1, version: 0)
      assert {:error, :conflict} = PackageStore.put(ws, "jido", "a", 2, version: 0)
      assert {:ok, 2} = PackageStore.put(ws, "jido", "a", 2, version: 1)
      assert {:error, :conflict} = PackageStore.delete(ws, "jido", "a", version: 1)
      assert :ok = PackageStore.delete(ws, "jido", "a", version: 2)
      assert {:error, :not_found} = PackageStore.get(ws, "jido", "a")
    end

    test "lists by prefix, by key, and a prefix is only text", %{workspace_id: ws} do
      for key <- ["b/2", "a/1", "b/1", "bx"], do: PackageStore.put(ws, "jido", key, key)
      PackageStore.put(ws, "jido", "b%", "odd")

      assert {:ok, [%{key: "b/1"}, %{key: "b/2"}]} = PackageStore.list(ws, "jido", "b/")
      assert {:ok, [%{key: "b%"}]} = PackageStore.list(ws, "jido", "b%")
      assert {:ok, [%{key: "a/1"}]} = PackageStore.list(ws, "jido", "", limit: 1)
    end
  end

  describe "with a run" do
    setup %{flow: flow} do
      %{run: execution_fixture(%{flow: flow})}
    end

    test "only that run sees its change until it succeeds", %{workspace_id: ws, run: run} do
      {:ok, 1} = PackageStore.put(ws, "jido", "a", "before")

      assert {:ok, 2} = PackageStore.put(ws, "jido", "a", "during", with_run: run.id)

      assert {:ok, %{value: "during", version: 2}} =
               PackageStore.get(ws, "jido", "a", with_run: run.id)

      assert {:ok, %{value: "before", version: 1}} = PackageStore.get(ws, "jido", "a")

      assert {:ok, [%{value: "during"}]} = PackageStore.list(ws, "jido", "", with_run: run.id)
      assert {:ok, [%{value: "before"}]} = PackageStore.list(ws, "jido", "")

      assert {:ok, _run} = Executions.mark_succeeded(run, %{})
      assert {:ok, %{value: "during", version: 2}} = PackageStore.get(ws, "jido", "a")
    end

    test "a run that fails changes nothing", %{workspace_id: ws, run: run} do
      {:ok, 1} = PackageStore.put(ws, "jido", "kept", "before")
      {:ok, 2} = PackageStore.put(ws, "jido", "kept", "during", with_run: run.id)
      :ok = PackageStore.delete(ws, "jido", "kept", with_run: run.id)
      {:ok, 1} = PackageStore.put(ws, "jido", "new", "during", with_run: run.id)

      assert {:error, :not_found} = PackageStore.get(ws, "jido", "kept", with_run: run.id)

      assert {:ok, _run} = Executions.mark_failed(run, %{"message" => "boom"})
      assert {:ok, %{value: "before", version: 1}} = PackageStore.get(ws, "jido", "kept")
      assert {:error, :not_found} = PackageStore.get(ws, "jido", "new")
    end

    test "a delete is kept when the run succeeds", %{workspace_id: ws, run: run} do
      {:ok, 1} = PackageStore.put(ws, "jido", "a", 1)
      :ok = PackageStore.delete(ws, "jido", "a", with_run: run.id)

      assert {:ok, [_kept]} = PackageStore.list(ws, "jido", "")
      assert {:ok, []} = PackageStore.list(ws, "jido", "", with_run: run.id)

      {:ok, _run} = Executions.mark_succeeded(run, %{})
      assert {:error, :not_found} = PackageStore.get(ws, "jido", "a")
    end

    test "checks the version against what the run sees", %{workspace_id: ws, run: run} do
      {:ok, 1} = PackageStore.put(ws, "jido", "a", 1)
      {:ok, 2} = PackageStore.put(ws, "jido", "a", 2, with_run: run.id, version: 1)

      assert {:error, :conflict} =
               PackageStore.put(ws, "jido", "a", 3, with_run: run.id, version: 1)

      assert {:ok, 3} = PackageStore.put(ws, "jido", "a", 3, with_run: run.id, version: 2)
    end
  end
end
