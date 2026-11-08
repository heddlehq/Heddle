defmodule HeddleNodes.Services.Spool do
  @moduledoc """
  Spool, the tables each workspace keeps inside Heddle, for the Spool nodes.

  Spool needs no credential: a run reaches the tables of its flow's workspace, which
  the runner pins in the context. heddle_core is only a test dependency of this app,
  so the store comes from the `:spool_client` config, see `HeddleCore.Spool.Client`.

  Values go through `HeddleNodes.Integration.json/3`, which parses before it fills in
  placeholders, and reach the database as parameters.
  """

  alias HeddleNodes.Integration

  @color "bg-primary/10 text-primary"

  @doc "Builds the definition of one Spool node."
  def definition(action, description, fields) do
    name = "Spool: #{action}"

    %{
      name: name,
      title: name,
      category: :database,
      group: "Spool",
      color: @color,
      description: description,
      icon: "hero-circle-stack-solid",
      inputs: [:exec],
      outputs: Integration.outputs(),
      show: true,
      ui_fields: [table_field() | fields]
    }
  end

  def table_field, do: %{type: :text, name: :table, label: "Table", default: ""}

  def rows_field do
    %{type: :textarea, name: :rows, label: "Rows", default: "{{form}}"}
  end

  def filter_field do
    %{type: :textarea, name: :filter, label: "Filter (JSON)", default: ""}
  end

  @doc """
  Calls `fun` with the store, the workspace of the run and the table's name, and
  answers through the node's outputs.
  """
  def run(context, fun) do
    client = Application.fetch_env!(:heddle_nodes, :spool_client)

    case fun.(client, context["workspace_id"], Integration.field(context, "table")) do
      {:ok, result} -> Integration.success(context, result)
      {:error, message} -> Integration.failure(context, message)
    end
  end

  @doc "The rows to write: one object, or a list of them."
  def rows(context) do
    case Integration.json(context, "rows") do
      {:ok, %{"rows" => rows}} when is_list(rows) -> objects(rows)
      {:ok, %{} = row} -> objects([row])
      {:ok, rows} when is_list(rows) -> objects(rows)
      {:ok, _other} -> {:error, "Rows: give one object, or a list of objects."}
      {:error, message} -> {:error, message}
    end
  end

  defp objects([]), do: {:error, "There are no rows to write."}

  defp objects(rows) do
    if Enum.all?(rows, &is_map/1),
      do: {:ok, rows},
      else: {:error, "Rows: each row must be an object, from column to value."}
  end

  @doc "The filter: an object from column to what it must be, or nothing."
  def filter(context) do
    case String.trim(context["filter"] || "") do
      "" ->
        {:ok, %{}}

      _filter ->
        case Integration.json(context, "filter") do
          {:ok, %{} = filter} -> {:ok, filter}
          {:ok, _other} -> {:error, ~s(Filter: give an object, like {"status": "open"}.)}
          {:error, message} -> {:error, message}
        end
    end
  end

  @doc "An object of values, from column to value."
  def values(context, name) do
    case Integration.json(context, name) do
      {:ok, %{} = values} -> {:ok, values}
      {:ok, _other} -> {:error, "Values: give an object, from column to value."}
      {:error, message} -> {:error, message}
    end
  end
end
