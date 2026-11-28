defmodule HeddleCore.Integrations.Hooks do
  @moduledoc """
  The addresses of the webhook triggers of integrations: a service calls
  `/hooks/:token` when something happens, and the flow starts from that node.

  Publishing a flow schedules `HeddleWorker.HookWorker`, which tells each service
  about the address of each such trigger the flow now has (and stops the ones it no
  longer has), as the manifest says (see `Bobbin.Integration.Webhook`). Deleting a
  flow schedules the same worker to stop them, with what it needs, since the rows go
  with the flow.

  The token stays the same across publishes, so an address the person pasted in the
  service by hand keeps working. What the service needs to know the webhook (its
  `secret`, the `id` it gave) is kept encrypted, under a key derived from
  `SECRET_KEY_BASE`, like credentials.
  """

  import Ecto.Query

  alias HeddleCore.Flows.Flow
  alias HeddleCore.Integrations.Hook
  alias HeddleCore.Repo

  @worker "HeddleWorker.HookWorker"
  @version 1

  @doc "The hooks of the flow `flow_id`."
  def list(flow_id), do: Repo.all(from h in Hook, where: h.flow_id == ^flow_id)

  @doc "The hook of a node, or nil."
  def get(flow_id, node_id), do: Repo.get_by(Hook, flow_id: flow_id, node_id: to_string(node_id))

  @doc "The hook at `/hooks/:token`, or nil."
  def get_by_token(token) when is_binary(token), do: Repo.get_by(Hook, token: token)

  @doc "The address of a hook, or of a token."
  def url(%Hook{token: token}), do: url(token)
  def url(token) when is_binary(token), do: public_url() <> "/hooks/" <> token

  @doc "A new token, which is the only secret of a hook's address."
  def new_token, do: Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)

  @doc "A new secret, for the services that sign their events with one Heddle gives."
  def new_secret, do: Base.encode16(:crypto.strong_rand_bytes(24), case: :lower)

  @doc "What the service needs to know the hook: `url`, `secret`, `id`."
  def webhook(%Hook{webhook: data}), do: decrypt(data)

  @doc """
  Keeps the hook of a node, made or changed. `attrs` holds `type`, `controls`,
  `webhook` (a map, kept encrypted), `manual` and `error`; the token stays the same.
  """
  def save(flow_id, node_id, token, attrs) do
    now = DateTime.utc_now(:second)

    hook = %Hook{
      flow_id: flow_id,
      node_id: to_string(node_id),
      token: token,
      type: attrs.type,
      controls: attrs.controls || %{},
      webhook: encrypt(attrs.webhook),
      manual: attrs[:manual] || false,
      error: attrs[:error],
      inserted_at: now,
      updated_at: now
    }

    Repo.insert!(hook,
      on_conflict: {:replace, [:type, :controls, :webhook, :manual, :error, :updated_at]},
      conflict_target: [:flow_id, :node_id],
      returning: true
    )
  end

  @doc "Removes a hook, once the service no longer calls it."
  def delete(%Hook{} = hook), do: Repo.delete(hook)

  @doc """
  Schedules the hooks of a flow just published to match its triggers. Only flows with
  integration nodes (named `Service: Step`) or hooks already can have something to do.
  """
  def sync_later(%Flow{} = published) do
    integrations? =
      Enum.any?(published.nodes || [], fn node ->
        String.contains?(to_string(node["type"] || node[:type]), ": ")
      end)

    if integrations? or list(published.id) != [] do
      %{"flow_id" => published.id}
      |> Oban.Job.new(
        queue: :default,
        worker: @worker,
        max_attempts: 3,
        unique: [keys: [:flow_id], period: 10, states: [:available, :scheduled]]
      )
      |> insert()
    end

    :ok
  end

  @doc """
  Schedules the hooks of a flow about to be deleted to be stopped with the service.
  The job carries what it needs, since the rows are deleted with the flow.
  """
  def forget_flow(%Flow{} = flow) do
    case list(flow.id) do
      [] ->
        :ok

      hooks ->
        %{
          "workspace_id" => flow.workspace_id,
          "stop" =>
            Enum.map(hooks, fn hook ->
              %{
                "type" => hook.type,
                "controls" => hook.controls,
                "manual" => hook.manual,
                "webhook" => Base.encode64(hook.webhook)
              }
            end)
        }
        |> Oban.Job.new(queue: :default, worker: @worker, max_attempts: 3)
        |> insert()

        :ok
    end
  end

  @doc "Reads what `forget_flow/1` put in a job."
  def decode_webhook(encoded) do
    with {:ok, data} <- Base.decode64(encoded), do: decrypt(data)
  end

  defp insert(job) do
    name = Application.get_env(:heddle_core, :oban_name, HeddleCore.Oban)
    Oban.insert(Enum.find([name, Oban], &Oban.whereis/1) || name, job)
  end

  defp public_url do
    :heddle_core
    |> Application.get_env(:public_url, "http://localhost:4000")
    |> String.trim_trailing("/")
  end

  ## Encryption

  defp encrypt(webhook) do
    iv = :crypto.strong_rand_bytes(12)
    plain = Jason.encode!(webhook || %{})
    {cipher, tag} = :crypto.crypto_one_time_aead(:aes_256_gcm, key(), iv, plain, "hook", true)
    <<@version, iv::binary-12, tag::binary-16, cipher::binary>>
  end

  defp decrypt(<<@version, iv::binary-12, tag::binary-16, cipher::binary>>) do
    case :crypto.crypto_one_time_aead(:aes_256_gcm, key(), iv, cipher, "hook", tag, false) do
      plain when is_binary(plain) -> {:ok, Jason.decode!(plain)}
      :error -> {:error, "The webhook can't be read. SECRET_KEY_BASE may have changed."}
    end
  end

  defp decrypt(_data), do: {:error, "The webhook can't be read."}

  defp key do
    secret = Application.fetch_env!(:heddle_core, :credentials_secret)
    :crypto.mac(:hmac, :sha256, secret, "heddle integration hooks")
  end
end
