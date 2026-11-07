defmodule HeddleNodes.Nodes.Sql.RunTransaction do
  use Bobbin.Node

  alias HeddleNodes.Services.Sql
  alias HeddleNodes.Services.Sql.Statement

  definition do
    Sql.definition(
      "Run Transaction",
      "Runs several statements, separated by semicolons. If one fails, none of them count.",
      [%{type: :textarea, name: :statements, label: "Statements", default: ""}]
    )
  end

  @impl true
  def handler(context, _input) do
    Sql.run(context, fn engine, conn ->
      statements = Statement.split(context["statements"] || "", engine.strings())

      with {:ok, results} <- run_all(engine, conn, statements, context) do
        {:ok, %{"results" => results, "count" => length(results)}}
      end
    end)
  end

  defp run_all(_engine, _conn, [], _context), do: {:error, "There are no statements to run."}

  defp run_all(engine, conn, statements, context) do
    engine.transaction(conn, fn conn ->
      statements
      |> Enum.reduce_while({:ok, []}, fn statement, {:ok, results} ->
        case Sql.execute(engine, conn, statement, context) do
          {:ok, result} -> {:cont, {:ok, [result | results]}}
          {:error, message} -> {:halt, {:error, message}}
        end
      end)
      |> then(fn
        {:ok, results} -> {:ok, Enum.reverse(results)}
        error -> error
      end)
    end)
  end
end
