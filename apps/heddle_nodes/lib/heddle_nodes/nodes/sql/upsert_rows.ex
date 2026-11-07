defmodule HeddleNodes.Nodes.Sql.UpsertRows do
  use Bobbin.Node

  alias HeddleNodes.Services.Sql

  definition do
    Sql.definition(
      "Upsert Rows",
      "Adds rows, and updates the ones whose key columns already exist.",
      [
        Sql.table_field(),
        Sql.rows_field(),
        %{type: :text, name: :key_columns, label: "Key columns", default: ""}
      ]
    )
  end

  @impl true
  def handler(context, _input) do
    Sql.run(context, fn engine, conn ->
      with {:ok, table} <- Sql.table(engine, context),
           {:ok, columns, rows} <- Sql.rows(context),
           {:ok, keys} <- keys(context, columns) do
        Sql.write_rows(engine, conn, columns, rows, &engine.upsert(table, columns, &1, keys))
      end
    end)
  end

  defp keys(context, columns) do
    keys = Sql.names(context, "key_columns")

    cond do
      keys == [] -> {:error, "Key columns: say which columns identify a row."}
      keys -- columns != [] -> {:error, "The rows have no #{Enum.join(keys -- columns, ", ")}."}
      true -> {:ok, keys}
    end
  end
end
