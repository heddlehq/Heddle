defmodule HeddleNodes.Services.Sql.StatementTest do
  use ExUnit.Case, async: true

  alias HeddleNodes.Services.Sql.Statement

  @context %{"name" => "Robert'); DROP TABLE users;--", "id" => 7, "body" => %{"age" => 30}}

  defp dollar(position), do: "$#{position}"

  describe "bind/5" do
    test "sends a placeholder as a parameter, never as text" do
      assert {:ok, "SELECT * FROM users WHERE name = $1 AND id = $2", params} =
               Statement.bind(
                 "SELECT * FROM users WHERE name = {{name}} AND id = {{id}}",
                 @context,
                 &dollar/1
               )

      assert params == [@context["name"], 7]
    end

    test "reads a dotted path" do
      assert {:ok, "SELECT $1", [30]} = Statement.bind("SELECT {{body.age}}", @context, &dollar/1)
    end

    test "turns a string that holds a placeholder into one parameter" do
      assert {:ok, "SELECT * FROM t WHERE a LIKE $1", ["%7%"]} =
               Statement.bind("SELECT * FROM t WHERE a LIKE '%{{id}}%'", @context, &dollar/1)
    end

    test "a quote in a value can't close the string around it" do
      assert {:ok, "SELECT $1", [param]} =
               Statement.bind("SELECT '{{name}}'", @context, &dollar/1)

      assert param == @context["name"]
    end

    test "keeps doubled quotes in a string with a placeholder" do
      assert {:ok, "SELECT $1", ["it's 7"]} =
               Statement.bind("SELECT 'it''s {{id}}'", @context, &dollar/1)
    end

    test "leaves strings without placeholders as they are" do
      assert {:ok, "SELECT 'it''s', $1", [7]} =
               Statement.bind("SELECT 'it''s', {{id}}", @context, &dollar/1)
    end

    test "ignores placeholders in comments" do
      template = "SELECT 1 -- {{id}}\n/* {{name}} */"

      assert {:ok, ^template, []} = Statement.bind(template, @context, &dollar/1)
    end

    test "refuses a placeholder in a quoted name" do
      assert {:error, message} = Statement.bind(~s(SELECT * FROM "{{name}}"), @context, &dollar/1)
      assert message =~ "name"
    end

    test "reads double quotes as strings where the dialect does" do
      assert {:ok, "SELECT ?", ["7"]} =
               Statement.bind(~s(SELECT "{{id}}"), @context, fn _position -> "?" end, 0, [?', ?"])
    end

    test "counts from the offset" do
      assert {:ok, "a = $4", [7]} = Statement.bind("a = {{id}}", @context, &dollar/1, 3)
    end

    test "reports a placeholder that never closes" do
      assert {:error, _message} = Statement.bind("SELECT {{id", @context, &dollar/1)
    end

    test "keeps text that isn't ASCII" do
      assert {:ok, "SELECT 'ação', $1", [7]} =
               Statement.bind("SELECT 'ação', {{id}}", @context, &dollar/1)
    end
  end

  describe "split/2" do
    test "splits on semicolons" do
      assert Statement.split("SELECT 1; SELECT 2;\n") == ["SELECT 1", "SELECT 2"]
    end

    test "keeps semicolons in strings and comments" do
      assert Statement.split("SELECT ';'; -- a;b\nSELECT 2") == ["SELECT ';'", "-- a;b\nSELECT 2"]
    end
  end
end
