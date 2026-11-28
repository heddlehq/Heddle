defmodule HeddleUI.ChatTextTest do
  use ExUnit.Case, async: true

  alias HeddleUI.ChatText

  defp html(text), do: text |> ChatText.to_html() |> Phoenix.HTML.safe_to_string()

  test "paragraphs, line breaks, bold, italic and code" do
    assert html("  Olá, **Bia**!\nTudo *bem*?\n\nUse `A-1002`.  ") ==
             "<p>Olá, <strong>Bia</strong>!<br>Tudo <em>bem</em>?</p><p>Use <code>A-1002</code>.</p>"
  end

  test "lists" do
    assert html("- Status: atrasado\n- Rastreio: JD998877") ==
             "<ul><li>Status: atrasado</li><li>Rastreio: JD998877</li></ul>"

    assert html("1. Confira\n2. Responda") == "<ol><li>Confira</li><li>Responda</li></ol>"
  end

  test "a message can't bring HTML of its own" do
    out = html(~s[<script>alert(1)</script> **<img src=x onerror=alert(1)>**])
    refute out =~ "<script"
    refute out =~ "<img"
    assert out =~ "&lt;script&gt;"
  end
end
