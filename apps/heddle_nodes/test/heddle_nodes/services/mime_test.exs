defmodule HeddleNodes.Services.MimeTest do
  use ExUnit.Case, async: true

  alias HeddleNodes.Services.Mime

  defp lines(lines), do: Enum.join(lines, "\r\n")

  describe "header/2" do
    test "decodes encoded words in any case, and joins the ones next to each other" do
      message =
        Mime.parse(
          lines([
            "SUBJECT: =?utf-8?b?UmVsYXTDs3Jpbw==?=",
            "From: =?ISO-8859-1?Q?Jos=E9_Silva?= <j@x.co>",
            "X-Long: =?UTF-8?Q?a?=",
            " =?UTF-8?Q?b?=",
            "",
            ""
          ])
        )

      assert Mime.header(message, "subject") == "Relatório"
      assert Mime.header(message, "from") == "José Silva <j@x.co>"
      assert Mime.header(message, "x-long") == "ab"
      assert Mime.header(message, "missing") == ""
    end

    test "survives an encoded word that isn't valid" do
      message = Mime.parse("Subject: =?UTF-8?Q?a=ZZ?=\r\n\r\n")

      assert is_binary(Mime.header(message, "subject"))
    end
  end

  describe "parse/1" do
    test "keeps the accents of a body sent as 8bit" do
      utf8 = "Content-Type: text/plain; charset=utf-8\r\n\r\nOlá"
      latin = "Content-Type: text/plain; charset=iso-8859-1\r\n\r\nOl" <> <<0xE1>>

      assert [part] = Mime.parse(utf8).parts
      assert Mime.text(part) == "Olá"

      assert [part] = Mime.parse(latin).parts
      assert Mime.text(part) == "Olá"
    end

    test "treats a message with no MIME headers as text" do
      assert [%{type: "text/plain", name: nil} = part] = Mime.parse("From: a\n\nHi\n").parts
      assert Mime.text(part) == "Hi\n"
    end

    test "reads nested multiparts, skipping what's around them" do
      raw =
        lines([
          ~s(Content-Type: multipart/mixed; boundary=outer),
          "",
          "This is a MIME message.",
          "--outer",
          ~s(Content-Type: multipart/alternative; boundary="in ner"),
          "",
          "--in ner",
          "Content-Type: text/plain",
          "",
          "text",
          "--in ner",
          "Content-Type: text/html",
          "",
          "<p>html</p>",
          "--in ner--",
          "--outer",
          "Content-Type: application/pdf",
          "Content-Disposition: attachment",
          "Content-Transfer-Encoding: BASE64",
          "",
          "aGVs",
          "bG8=",
          "--outer--",
          "The end."
        ])

      assert [text, html, file] = Mime.parse(raw).parts
      assert %{type: "text/plain", body: "text"} = text
      assert %{type: "text/html", body: "<p>html</p>"} = html
      assert %{type: "application/pdf", name: "attachment", body: "hello"} = file
    end

    test "keeps the last part when the closing boundary is missing" do
      raw = lines(["Content-Type: multipart/mixed; boundary=b", "", "--b", "", "text"])

      assert [%{body: "text"}] = Mime.parse(raw).parts
    end

    test "reads the file names mail clients send" do
      name = fn header -> hd(Mime.parse(header <> "\r\n\r\nx").parts).name end

      assert name.(~s(Content-Disposition: attachment; filename="a b.pdf")) == "a b.pdf"

      assert name.("Content-Disposition: attachment; filename*=UTF-8''relat%C3%B3rio.pdf") ==
               "relatório.pdf"

      assert name.(~s(Content-Type: application/pdf; name="=?UTF-8?B?w6kucGRm?=")) == "é.pdf"
      assert name.("Content-Type: text/plain") == nil
    end

    test "leaves a body it can't decode as it came" do
      raw = "Content-Transfer-Encoding: base64\r\n\r\nnot base64!"

      assert [%{body: body}] = Mime.parse(raw).parts
      assert is_binary(body)
    end
  end
end
