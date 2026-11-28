defmodule HeddleNodes.BobbinHost do
  @moduledoc """
  What Heddle gives the nodes written with Bobbin, see `Bobbin.Host`: the credentials
  of each workspace, runs of the flows that begin at a package's trigger, a store for
  what a package keeps between runs, and the AI models of the AI page, whose calls the
  step running pays for.

  heddle_core is only a test dependency of this app, so they come from config, as
  `:credentials_client`, `:runs_client` (`HeddleWorker.PackageRuns`) and
  `:store_client` (`HeddleCore.PackageStore`).
  """

  @behaviour Bobbin.Host

  alias HeddleNodes.Services.AI
  alias HeddleNodes.Usage

  @impl true
  def credential(workspace_id, name, kind, opts) do
    client = Application.fetch_env!(:heddle_nodes, :credentials_client)
    args = [workspace_id, name, kind]

    if opts == [], do: apply(client, :fetch, args), else: apply(client, :fetch, args ++ [opts])
  end

  @impl true
  def start_runs(request), do: runs().start_runs(request)

  @impl true
  def cancel_run(workspace_id, run_id), do: runs().cancel_run(workspace_id, run_id)

  @impl true
  def resume_run(workspace_id, run_id, key, value),
    do: runs().resume_run(workspace_id, run_id, key, value)

  @impl true
  def store_get(workspace_id, namespace, key, opts),
    do: store().get(workspace_id, namespace, key, opts)

  @impl true
  def store_put(workspace_id, namespace, key, value, opts),
    do: store().put(workspace_id, namespace, key, value, opts)

  @impl true
  def store_delete(workspace_id, namespace, key, opts),
    do: store().delete(workspace_id, namespace, key, opts)

  @impl true
  def store_list(workspace_id, namespace, prefix, opts),
    do: store().list(workspace_id, namespace, prefix, opts)

  @doc """
  How to call a model for a node: its `credential` and `model` fields, or what the AI
  page sets for `capability`, as `HeddleNodes.Services.AI` works it out for the AI
  nodes. `options` hold the API key, so they never go in a node's output.
  """
  @impl true
  def ai_connection(context, capability) do
    with {:ok, plan} <- AI.plan(context, capability),
         {:ok, model, request} <- llm().connect(Keyword.put(plan, :tools, [])) do
      {:ok, %{model: model, options: Keyword.delete(request, :tools)}}
    end
  end

  @doc """
  Adds a model call to the step running. It must come from the process of the node's
  handler, where the step's usage is kept, see `HeddleNodes.Usage`.
  """
  @impl true
  def record_usage(usage), do: Usage.record(usage)

  defp llm, do: Application.fetch_env!(:heddle_nodes, :llm_client)
  defp runs, do: Application.fetch_env!(:heddle_nodes, :runs_client)
  defp store, do: Application.fetch_env!(:heddle_nodes, :store_client)
end
