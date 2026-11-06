defmodule HeddleNodes.Integration do
  @moduledoc """
  What the nodes that reach other services have in common.

  They all use a stored credential, and they answer through the `success` and
  `error` outputs, so a flow can handle a service being down.
  """

  alias HeddleNodes.Template

  def outputs, do: ["success", "error"]

  def credential_field(kind) do
    %{type: :credential, name: :credential, label: "Credential", kind: kind, default: ""}
  end

  @doc """
  Returns the values of the credential the node picked.

  heddle_core is only a test dependency of this app, so the store comes from config.
  """
  def credential(context, kind) do
    Application.fetch_env!(:heddle_nodes, :credentials_client).fetch(context["credential"], kind)
  end

  def field(context, name), do: Template.render(context[name], context)

  def success(context, result), do: {:ok, Map.put(context, "result", result), "success"}

  def failure(context, message) do
    {:ok, Map.put(context, "result", %{"error" => message}), "error"}
  end

  def req_options(options) do
    Keyword.merge(
      [retry: false, plug: Application.get_env(:heddle_nodes, :req_plug)],
      options
    )
  end

  @doc """
  Makes content safe to keep in a run's context, which is saved as JSON.
  """
  def to_text(content) do
    if String.valid?(content) do
      %{"content" => content}
    else
      %{"content" => Base.encode64(content), "encoding" => "base64"}
    end
  end
end
