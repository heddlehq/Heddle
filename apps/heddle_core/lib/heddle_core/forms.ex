defmodule HeddleCore.Forms do
  @moduledoc """
  Forms anyone with the link can fill in, each one a Form Trigger of a flow.

  The fields and texts of a form are controls of its node (see `Heddle.Form`), so they
  are part of the draft and published with the flow. Its link is not: it lives in a
  `HeddleCore.Forms.Form`, made the first time someone looks for it or the flow is
  published, and stays the same across publishes until an editor makes a new one. A
  copied node is another node, with a link of its own.

  The link shows what is published, as webhooks do: a flow that was never published,
  or whose published version doesn't have the node, has no form there. Sending it
  starts a run of the published version from that node, with what was sent in
  `form`. People who can run the flow can try the draft through `draft/3`.
  """

  import Ecto.Query

  alias Heddle.Graph
  alias HeddleCore.Accounts.Scope
  alias HeddleCore.{Executions, Flows, Repo, Spool, Workspaces}
  alias HeddleCore.Flows.{Flow, Versions}
  alias HeddleCore.Forms.Form

  @type_name "Form Trigger"

  @doc "The type of the node a form belongs to."
  def node_type, do: @type_name

  @doc """
  The form of a Form Trigger in the draft of `flow`, which the caller can see. Makes
  it the first time.

  Returns `{:ok, form}`, or `{:error, :not_found}` when the draft has no such node.
  """
  def link(%Scope{} = scope, %Flow{} = flow, node_id) do
    with :ok <- Workspaces.authorize(scope, :view, flow.workspace_id),
         %Graph.Node{type: @type_name} <- flow |> Graph.new() |> Graph.get(to_string(node_id)) do
      {:ok, ensure(flow.id, to_string(node_id))}
    else
      {:error, :forbidden} -> {:error, :forbidden}
      _other -> {:error, :not_found}
    end
  end

  @doc """
  Makes sure every Form Trigger of a flow just published has its link.
  """
  def register_flow(%Flow{} = published) do
    published
    |> Graph.new()
    |> Graph.of_type(@type_name)
    |> Enum.each(&ensure(published.id, &1.id))

    :ok
  end

  defp ensure(flow_id, node_id) do
    Repo.insert_all(
      Form,
      [
        %{
          flow_id: flow_id,
          node_id: node_id,
          token: Form.new_token(),
          inserted_at: DateTime.utc_now(:second),
          updated_at: DateTime.utc_now(:second)
        }
      ],
      on_conflict: :nothing,
      conflict_target: [:flow_id, :node_id]
    )

    Repo.get_by!(Form, flow_id: flow_id, node_id: node_id)
  end

  @doc """
  Gives a form a new link, so the old one stops working. Editors and up.
  """
  def regenerate(%Scope{} = scope, %Flow{} = flow, node_id) do
    with :ok <- Workspaces.authorize(scope, :edit, flow.workspace_id),
         {:ok, form} <- link(scope, flow, node_id) do
      form |> Ecto.Changeset.change(token: Form.new_token()) |> Repo.update()
    end
  end

  @doc """
  The form published at `token`, to show it.

  Returns `{:ok, page}`, `{:error, :closed, page}` when it doesn't take answers now,
  or `{:error, :not_found}`. A page has the `fields` and texts the node sets.
  """
  def public(token) do
    with {:ok, _form, _flow, node} <- published(token) do
      page = page(node)
      if page.accepting, do: {:ok, page}, else: {:error, :closed, page}
    end
  end

  @doc """
  Sends the form published at `token` with `params`, by field key, and starts a run
  of the published version from its node.

  Returns `{:ok, page}`, `{:error, :invalid, page, errors, values}` (see
  `Heddle.Form.cast/2`), `{:error, :closed, page}`, `{:error, :not_found}`, or
  `{:error, :not_started, page}` when the run could not be queued.
  """
  def submit(token, params) do
    with {:ok, _form, flow, node} <- published(token) do
      page = page(node)

      with true <- page.accepting || {:error, :closed, page},
           {:ok, values} <- cast(page, params),
           {:ok, _execution} <- Executions.start_execution(flow, input(node, values)) do
        {:ok, page}
      else
        {:error, :invalid, errors, values} -> {:error, :invalid, page, errors, values}
        {:error, :closed, page} -> {:error, :closed, page}
        {:error, _reason} -> {:error, :not_started, page}
      end
    end
  end

  defp published(token) when is_binary(token) do
    with %Form{} = form <- Repo.get_by(Form, token: token),
         %Flow{} = flow <- published_flow(form.flow_id),
         %Graph.Node{type: @type_name} = node <- flow |> Graph.new() |> Graph.get(form.node_id) do
      {:ok, form, flow, node}
    else
      _other -> {:error, :not_found}
    end
  end

  defp published(_token), do: {:error, :not_found}

  # The same cache webhooks use, which a publish clears.
  defp published_flow(flow_id) do
    case Flows.Cache.get(flow_id) do
      nil ->
        with %Flow{} = flow <- Flows.get_flow(flow_id),
             %Flow{} = published <- Versions.published_flow(flow) do
          Flows.Cache.put(published)
          published
        end

      cached ->
        cached
    end
  end

  @doc """
  The form of a Form Trigger in the draft, to try it. For those who can run the flow.

  Returns `{:ok, page}` or `{:error, :forbidden | :not_found}`.
  """
  def draft(%Scope{} = scope, %Flow{} = flow, node_id) do
    with :ok <- Workspaces.authorize(scope, :run, flow.workspace_id),
         {:ok, node} <- draft_node(flow, node_id) do
      {:ok, page(node)}
    end
  end

  @doc """
  Sends the form of a Form Trigger in the draft, and runs the draft from it, as the
  editor runs a flow. It runs whether or not the form takes answers.

  Returns `{:ok, execution, page}`, `{:error, :invalid, page, errors, values}` or
  `{:error, reason}`.
  """
  def submit_draft(%Scope{} = scope, %Flow{} = flow, node_id, params) do
    with :ok <- Workspaces.authorize(scope, :run, flow.workspace_id),
         {:ok, node} <- draft_node(flow, node_id) do
      page = page(node)

      case cast(page, params) do
        {:ok, values} ->
          case Executions.run(scope, flow, input(node, values), version: :draft) do
            {:ok, execution} -> {:ok, execution, page}
            {:error, reason} -> {:error, reason}
          end

        {:error, :invalid, errors, values} ->
          {:error, :invalid, page, errors, values}
      end
    end
  end

  defp draft_node(flow, node_id) do
    case flow |> Graph.new() |> Graph.get(to_string(node_id)) do
      %Graph.Node{type: @type_name} = node -> {:ok, node}
      _other -> {:error, :not_found}
    end
  end

  @doc """
  Creates a Spool table with a column for each field of a Form Trigger in the draft,
  of the type that holds it. Editors and up.
  """
  def create_table(%Scope{} = scope, %Flow{} = flow, node_id, name) do
    with :ok <- Workspaces.authorize(scope, :edit, flow.workspace_id),
         {:ok, node} <- draft_node(flow, node_id) do
      columns =
        node
        |> page()
        |> Map.fetch!(:fields)
        |> Enum.reject(&(&1["key"] == "" or &1["key"] in Spool.Column.reserved()))
        |> Enum.uniq_by(&String.downcase(&1["key"]))
        |> Enum.map(&%{"name" => &1["key"], "type" => column_type(&1["type"])})

      Spool.create_table(scope, %{"name" => name, "columns" => columns})
    end
  end

  defp column_type("number"), do: "number"
  defp column_type("date"), do: "date"
  defp column_type("checkbox"), do: "boolean"
  defp column_type(_type), do: "text"

  @doc """
  What a page shows, from the controls of a Form Trigger.
  """
  def page(%Graph.Node{controls: controls}) do
    %{
      title: text(controls["title"]),
      description: text(controls["description"]),
      fields: Heddle.Form.parse!(controls["fields"]),
      submit_label: text(controls["submit_label"]),
      success_message: text(controls["success_message"]),
      redirect_url: redirect_url(controls["redirect_url"]),
      accepting: controls["accepting"] not in ["no", "false", false]
    }
  end

  defp text(value) when is_binary(value), do: String.trim(value)
  defp text(_value), do: ""

  # Only a web address: a person who opens the form is sent there.
  defp redirect_url(value) when is_binary(value) do
    url = String.trim(value)

    case URI.parse(url) do
      %URI{scheme: scheme, host: host}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        url

      _other ->
        nil
    end
  end

  defp redirect_url(_value), do: nil

  defp cast(page, params) when is_map(params) do
    case Heddle.Form.cast(page.fields, params) do
      {:ok, values} -> {:ok, values}
      {:error, errors, values} -> {:error, :invalid, errors, values}
    end
  end

  defp cast(page, _params), do: cast(page, %{})

  defp input(node, values) do
    %{
      "trigger" => "form",
      "node_id" => node.id,
      "form" => values,
      "form_submitted_at" => DateTime.utc_now(:second) |> DateTime.to_iso8601()
    }
  end

  @doc "The forms of a flow, by node id."
  def list_by_flow(flow_id) do
    Repo.all(from f in Form, where: f.flow_id == ^flow_id)
  end
end
