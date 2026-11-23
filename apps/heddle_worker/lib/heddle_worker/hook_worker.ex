defmodule HeddleWorker.HookWorker do
  @moduledoc """
  Tells services about the webhook triggers of a flow, see
  `HeddleCore.Integrations.Hooks`.

  With `flow_id`, after a publish: registers the address of each webhook trigger the
  published version has, again when its fields changed or the last try failed, and
  stops the ones it no longer has. With `stop`, after a flow was deleted: stops the
  hooks the job carries.

  A service that refuses is recorded on the hook, for the node's drawer to show, and
  the job fails so Oban tries again.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias Heddle.Graph
  alias HeddleCore.Flows
  alias HeddleCore.Flows.Versions
  alias HeddleCore.Integrations.{Hook, Hooks}
  alias HeddleNodes.Manifests

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"flow_id" => flow_id}}) do
    case Flows.get_flow(flow_id) do
      nil -> :ok
      flow -> sync(flow, Versions.published_flow(flow))
    end
  end

  def perform(%Oban.Job{args: %{"stop" => hooks, "workspace_id" => workspace_id}}) do
    for hook <- hooks, not hook["manual"], trigger = Manifests.webhook_trigger(hook["type"]) do
      with {:ok, webhook} <- Hooks.decode_webhook(hook["webhook"]),
           {:error, message} <- unregister(trigger, hook["controls"], workspace_id, webhook) do
        Logger.warning("Could not stop #{hook["type"]}: #{message}")
      end
    end

    :ok
  end

  @doc "Makes the hooks of `flow` match the webhook triggers of its published version."
  def sync(flow, published) do
    nodes = if published, do: trigger_nodes(published), else: %{}
    hooks = Hooks.list(flow.id)

    for %Hook{} = hook <- hooks, not Map.has_key?(nodes, hook.node_id) do
      stop(flow, hook)
    end

    hooks = Map.new(hooks, &{&1.node_id, &1})

    errors =
      Enum.flat_map(nodes, fn {node_id, {node, trigger}} ->
        hook = hooks[node_id]

        with true <- changed?(hook, node),
             {:error, message} <- start(flow, node, trigger, hook) do
          ["#{node.type} (#{node_id}): #{message}"]
        else
          _unchanged_or_ok -> []
        end
      end)

    if errors == [], do: :ok, else: {:error, Enum.join(errors, "; ")}
  end

  defp trigger_nodes(published) do
    for node <- Graph.new(published).nodes,
        trigger = Manifests.webhook_trigger(node.type),
        into: %{} do
      {node.id, {node, trigger}}
    end
  end

  defp changed?(nil, _node), do: true

  defp changed?(%Hook{} = hook, node) do
    hook.type != node.type or hook.controls != (node.controls || %{}) or hook.error != nil
  end

  # Registers the address of a node with the service, after stopping the one it had.
  defp start(flow, node, trigger, hook) do
    previous = hook && webhook!(hook)
    if hook && not hook.manual && hook.error == nil, do: stop_remote(flow, hook, previous)

    token = (hook && hook.token) || Hooks.new_token()
    webhook = %{"url" => Hooks.url(token), "secret" => Hooks.new_secret()}
    controls = node.controls || %{}
    attrs = %{type: node.type, controls: controls}

    case register(trigger, controls, flow.workspace_id, webhook) do
      {:ok, :manual} ->
        # The person pasted the address already, with the secret it had.
        webhook = if hook && hook.manual, do: previous, else: webhook
        Hooks.save(flow.id, node.id, token, Map.merge(attrs, %{webhook: webhook, manual: true}))
        :ok

      {:ok, registered} ->
        Hooks.save(flow.id, node.id, token, Map.merge(attrs, %{webhook: registered}))
        :ok

      {:error, message} ->
        Logger.warning("Could not register #{node.type} in flow #{flow.id}: #{message}")
        Hooks.save(flow.id, node.id, token, Map.merge(attrs, %{webhook: webhook, error: message}))
        {:error, message}
    end
  end

  defp stop(flow, hook) do
    if not hook.manual and hook.error == nil, do: stop_remote(flow, hook, webhook!(hook))
    Hooks.delete(hook)
  end

  defp stop_remote(flow, hook, webhook) do
    with trigger when not is_nil(trigger) <- Manifests.webhook_trigger(hook.type),
         {:error, message} <- unregister(trigger, hook.controls, flow.workspace_id, webhook) do
      Logger.warning("Could not stop #{hook.type} in flow #{flow.id}: #{message}")
    end
  end

  defp webhook!(hook) do
    case Hooks.webhook(hook) do
      {:ok, webhook} -> webhook
      {:error, _message} -> %{}
    end
  end

  defp register(trigger, controls, workspace_id, webhook) do
    Manifests.register_webhook(
      trigger.manifest,
      trigger.trigger.name,
      context(controls, workspace_id),
      webhook
    )
  end

  defp unregister(trigger, controls, workspace_id, webhook) do
    Manifests.unregister_webhook(
      trigger.manifest,
      trigger.trigger.name,
      context(controls, workspace_id),
      webhook
    )
  end

  defp context(controls, workspace_id),
    do: Map.merge(controls || %{}, %{"workspace_id" => workspace_id})
end
