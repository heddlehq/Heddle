defmodule HeddleNodes.Template do
  @moduledoc """
  Reads values from a run's context, and fills `{{name}}` placeholders with them. It
  lives in Bobbin, as `Bobbin.Template`, so the integrations fill their fields the same
  way.
  """

  defdelegate fetch(context, path), to: Bobbin.Template
  defdelegate render(template, context), to: Bobbin.Template
  defdelegate json(template, context, check \\ fn _value -> :ok end), to: Bobbin.Template
end
