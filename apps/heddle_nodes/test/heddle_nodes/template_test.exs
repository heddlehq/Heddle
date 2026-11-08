defmodule HeddleNodes.TemplateTest do
  use ExUnit.Case, async: true

  alias HeddleNodes.Template

  describe "fetch/2" do
    test "reads a key of the context" do
      assert Template.fetch(%{"result" => 6}, "result") == 6
    end

    test "prefers a flow variable" do
      assert Template.fetch(%{"x" => 1, "variables" => %{"x" => 2}}, "x") == 2
    end

    test "follows a dotted path" do
      assert Template.fetch(%{"body" => %{"user" => %{"name" => "Ana"}}}, "body.user.name") ==
               "Ana"
    end

    test "picks an item of a list by its position" do
      context = %{"body" => %{"items" => [%{"name" => "a"}, %{"name" => "b"}]}}

      assert Template.fetch(context, "body.items.1.name") == "b"
      assert Template.fetch(context, "body.items.5.name") == nil
      assert Template.fetch(context, "body.items.first") == nil
    end

    test "is nil for what isn't there" do
      assert Template.fetch(%{"body" => %{}}, "body.user.name") == nil
      assert Template.fetch(%{"body" => "text"}, "body.user") == nil
    end
  end

  describe "render/2" do
    test "fills in the values" do
      assert Template.render("Hi {{ body.name }}!", %{"body" => %{"name" => "Ana"}}) == "Hi Ana!"
    end

    test "writes maps and lists as JSON" do
      assert Template.render("{{result}}", %{"result" => %{"a" => [1]}}) == ~s({"a":[1]})
    end

    test "leaves what isn't there empty" do
      assert Template.render("[{{missing}}]", %{}) == "[]"
    end
  end
end
