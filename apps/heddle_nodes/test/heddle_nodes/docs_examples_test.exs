defmodule HeddleNodes.DocsExamplesTest do
  # The flows the documentation offers to import, in docs/examples/. Each must be
  # one a person can import and publish as it is.
  use ExUnit.Case, async: true

  alias HeddleCore.Flows.{GraphValidator, Import}

  @pattern Path.join(HeddleNodes.Docs.root(), "docs/examples/*.json")
  @examples Path.wildcard(@pattern)

  test "there are examples" do
    assert Path.wildcard(@pattern) != []
  end

  for path <- @examples do
    @path path

    test "#{Path.basename(path)} imports and could be published" do
      json = File.read!(@path)

      assert {:ok, graph} = Import.read(json)

      assert :ok =
               GraphValidator.validate(graph["nodes"], graph["connections"],
                 manifest: HeddleNodes
               )

      assert :ok = GraphValidator.validate_comments(graph["comments"] || [])
    end
  end
end
