defmodule HeddleNodes.Nodes.Sql.SelectRows do
  use Bobbin.Node

  alias HeddleNodes.Integration
  alias HeddleNodes.Services.Sql

  @default_limit 100

  definition do
    Sql.definition(
      "Select Rows",
      "Reads rows from a table, without writing SQL.",
      [
        Sql.table_field(),
        %{type: :text, name: :columns, label: "Columns (empty for all)", default: ""},
        Sql.where_field(),
        %{type: :text, name: :order_by, label: "Order by", default: ""},
        %{type: :text, name: :limit, label: "Limit", default: "100"},
        %{type: :text, name: :offset, label: "Skip", default: "0"}
      ]
    )
  end

  @impl true
  def handler(context, _input) do
    Sql.run(context, fn engine, conn ->
      with {:ok, table} <- Sql.table(engine, context),
           {:ok, where, params} <- where(engine, context),
           {:ok, order, more} <- order(engine, context, length(params)) do
        sql = "SELECT #{columns(engine, context)} FROM #{table}#{where}#{order}"
        limit = Integration.number(context, "limit", @default_limit)
        offset = Integration.number(context, "offset", 0)

        Sql.query(engine, conn, engine.paginate(sql, order != "", limit, offset), params ++ more)
      end
    end)
  end

  defp columns(engine, context) do
    case Sql.names(context, "columns") do
      [] -> "*"
      names -> Enum.map_join(names, ", ", &engine.quote_name/1)
    end
  end

  defp where(engine, context) do
    clause(engine, context, "where", " WHERE ", 0)
  end

  defp order(engine, context, offset) do
    clause(engine, context, "order_by", " ORDER BY ", offset)
  end

  defp clause(engine, context, field, keyword, offset) do
    case String.trim(context[field] || "") do
      "" ->
        {:ok, "", []}

      template ->
        with {:ok, sql, params} <- Sql.bind(engine, template, context, offset) do
          {:ok, keyword <> sql, params}
        end
    end
  end
end
