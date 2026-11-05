defmodule HeddleCore.ReleaseTest do
  use ExUnit.Case, async: true

  test "no module calls Mix at runtime, because releases do not ship it" do
    mix_calls =
      for module <- Application.spec(:heddle_core, :modules),
          {:ok, {_module, [imports: imports]}} =
            :beam_lib.chunks(:code.which(module), [:imports]),
          {imported, function, arity} <- imports,
          mix_module?(imported) do
        {module, imported, function, arity}
      end

    assert mix_calls == []
  end

  defp mix_module?(module) do
    module == Mix or module |> Atom.to_string() |> String.starts_with?("Elixir.Mix.")
  end
end
