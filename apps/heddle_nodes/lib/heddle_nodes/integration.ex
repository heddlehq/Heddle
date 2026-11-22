defmodule HeddleNodes.Integration do
  @moduledoc """
  What the nodes that reach other services have in common. It lives in Bobbin, as
  `Bobbin.Service`, so the integrations in heddlehq/integrations use it too; Heddle
  plugs in as `HeddleNodes.BobbinHost`.
  """

  defdelegate outputs, to: Bobbin.Service
  defdelegate definition(service, action, description, fields), to: Bobbin.Service
  defdelegate credential_field(kind), to: Bobbin.Service
  defdelegate credential(context, kind, opts \\ []), to: Bobbin.Service
  defdelegate run(context, kind, fun), to: Bobbin.Service
  defdelegate field(context, name), to: Bobbin.Service
  defdelegate content(context, name), to: Bobbin.Service
  defdelegate media(context, name), to: Bobbin.Service
  defdelegate json(context, name, check \\ fn _value -> :ok end), to: Bobbin.Service
  defdelegate number(context, name, default), to: Bobbin.Service
  defdelegate success(context, result), to: Bobbin.Service
  defdelegate failure(context, message), to: Bobbin.Service
  defdelegate req_options(options), to: Bobbin.Service
  defdelegate tls_options(host), to: Bobbin.Service
  defdelegate to_file(data, media_type), to: Bobbin.Service
  defdelegate to_value(value), to: Bobbin.Service
  defdelegate to_text(content), to: Bobbin.Service
end
