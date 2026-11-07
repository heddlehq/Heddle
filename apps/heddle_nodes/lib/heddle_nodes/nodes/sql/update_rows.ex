defmodule HeddleNodes.Nodes.Sql.UpdateRows do
  use Bobbin.Node

  alias HeddleNodes.Integration
  alias HeddleNodes.Services.Sql

  definition do
    Sql.definition(
      "Update Rows",
      "Changes the rows that match. To change every row, write 1 = 1 in Where.",
      [
        Sql.table_field(),
        %{type: :textarea, name: :changes, label: "New values", default: ""},
        Sql.where_field()
      ]
    )
  end

  @impl true
  def handler(context, _input) do
    Sql.run(context, fn engine, conn ->
      with {:ok, table} <- Sql.table(engine, context),
           {:ok, changes} <- changes(context),
           {:ok, where} <- Sql.required_where(context) do
        marks = Enum.with_index(changes, 1)
        set = Enum.map_join(marks, ", ", &assignment(engine, &1))

        with {:ok, where, params} <- Sql.bind(engine, where, context, length(changes)) do
          values = Enum.map(changes, &elem(&1, 1))

          Sql.query(engine, conn, "UPDATE #{table} SET #{set} WHERE #{where}", values ++ params)
        end
      end
    end)
  end

  defp assignment(engine, {{column, _value}, position}) do
    "#{engine.quote_name(column)} = #{engine.placeholder(position)}"
  end

  defp changes(context) do
    case Integration.json(context, "changes") do
      {:ok, %{} = changes} when map_size(changes) > 0 -> {:ok, Map.to_list(changes)}
      {:ok, _other} -> {:error, "New values: give an object, from column to value."}
      {:error, message} -> {:error, message}
    end
  end
end
