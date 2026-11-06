defmodule HeddleUI.CoreComponentsInputTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias HeddleUI.CoreComponents

  defp form_field(name, value) do
    to_form(%{to_string(name) => value}, as: :thing)[name]
  end

  test "a text input shows the value of its field" do
    html =
      render_component(&CoreComponents.input/1, field: form_field(:name, "Ana"), type: "text")

    assert html =~ ~s(value="Ana")
  end

  test "a select marks the value of its field" do
    html =
      render_component(&CoreComponents.input/1,
        field: form_field(:kind, "b"),
        type: "select",
        options: [{"A", "a"}, {"B", "b"}]
      )

    assert html =~ ~s(<option selected value="b">)
  end

  test "an explicit value wins over the field" do
    html =
      render_component(&CoreComponents.input/1,
        field: form_field(:name, "Ana"),
        type: "text",
        value: "Bia"
      )

    assert html =~ ~s(value="Bia")
  end
end
