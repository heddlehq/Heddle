defmodule HeddleNodes.TemplateJsonTest do
  use ExUnit.Case, async: true

  alias HeddleNodes.Template

  @context %{"name" => ~s(a"b), "age" => 30, "tags" => ["x"], "body" => %{"id" => 1}}

  test "a placeholder outside a string keeps the type of the value" do
    assert {:ok, %{"age" => 30, "tags" => ["x"], "id" => 1}} =
             Template.json(~s({"age": {{age}}, "tags": {{tags}}, "id": {{body.id}}}), @context)
  end

  test "a placeholder inside a string can't break out of it" do
    assert {:ok, %{"name" => ~s(hi a"b)}} = Template.json(~s({"name": "hi {{name}}"}), @context)
  end

  test "fills in the keys" do
    assert {:ok, %{"30" => true}} = Template.json(~s({"{{age}}": true}), @context)
  end

  test "reports JSON that doesn't parse" do
    assert {:error, message} = Template.json(~s({"a": ), @context)
    assert message =~ "JSON"
  end

  test "lets the caller refuse a value" do
    check = fn value -> if is_list(value), do: {:error, "no lists"}, else: :ok end

    assert {:error, "no lists"} = Template.json(~s({"tags": {{tags}}}), @context, check)
    assert {:ok, %{"age" => 30}} = Template.json(~s({"age": {{age}}}), @context, check)
  end
end
