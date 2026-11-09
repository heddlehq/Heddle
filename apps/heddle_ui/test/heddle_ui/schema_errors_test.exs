defmodule HeddleUI.SchemaErrorsTest do
  use ExUnit.Case, async: true

  alias HeddleUI.SchemaErrors

  @fields [%{"key" => "name"}, %{"key" => "address"}]

  defp issue(path, code, params),
    do: %{"path" => path, "code" => code, "message" => "in English", "params" => params}

  test "puts each error by its field, the first one only, and the rest apart" do
    issues = [
      issue("name", "required", %{}),
      issue("name", "too_small", %{"bound" => "min", "limit" => 2, "unit" => "characters"}),
      issue("address.city", "required", %{}),
      issue("coupon", "unknown_key", %{}),
      %{"path" => "", "code" => "invalid_union", "message" => "Pick a plan or a coupon"}
    ]

    assert SchemaErrors.by_field(issues, @fields) ==
             {%{"name" => "Fill in this field.", "address" => "Fill in this field."},
              ["Check this field.", "Pick a plan or a coupon"]}
  end

  test "says each error in the language of the request" do
    Gettext.with_locale(HeddleUI.Gettext, "pt_BR", fn ->
      min = issue("name", "too_small", %{"bound" => "min", "limit" => 3, "unit" => "characters"})
      assert SchemaErrors.message(min) == "Use pelo menos 3 caracteres."

      assert SchemaErrors.message(issue("e", "invalid_format", %{"format" => "email"})) ==
               "Digite um e-mail válido."

      assert SchemaErrors.message(issue("n", "too_small", %{"bound" => "gt", "limit" => 0.0})) ==
               "Digite mais que 0."
    end)
  end

  test "the author's message in the visitor's language, or the usual one in it" do
    issue =
      issue("name", "too_small", %{"bound" => "min", "limit" => 3, "unit" => "characters"})
      |> Map.put("messages", %{"en" => "Your name, please"})

    assert SchemaErrors.message(issue) == "Your name, please"

    Gettext.with_locale(HeddleUI.Gettext, "pt_BR", fn ->
      assert SchemaErrors.message(issue) == "Use pelo menos 3 caracteres."

      issue = Map.put(issue, "messages", %{"en" => "Your name, please", "pt_BR" => "Seu nome"})
      assert SchemaErrors.message(issue) == "Seu nome"
    end)
  end

  test "a message the schema's author wrote is shown as it is" do
    assert SchemaErrors.message(%{
             "path" => "cpf",
             "code" => "too_small",
             "message" => "Informe o CPF"
           }) ==
             "Informe o CPF"
  end
end
