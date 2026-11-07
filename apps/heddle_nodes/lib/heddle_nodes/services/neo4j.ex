defmodule HeddleNodes.Services.Neo4j do
  @moduledoc """
  Neo4j through its Query API, which self-managed servers and Aura both have.
  """

  alias HeddleNodes.Integration
  alias HeddleNodes.Services.Sql.Statement

  @timeout :timer.minutes(2)
  @service %{
    title: "Neo4j",
    category: :database,
    group: "Neo4j",
    credential: "neo4j",
    icon: "logo-neo4j"
  }

  def definition(action, description, fields) do
    Integration.definition(@service, action, description, fields)
  end

  def run(context, fun), do: Integration.run(context, "neo4j", fun)

  @doc """
  Binds what a field holds and runs it.
  """
  def execute(neo4j, template, context) do
    with {:ok, cypher, params} <-
           Statement.bind(template, context, &"$p#{&1}", 0, [?', ?"]) do
      request =
        Integration.req_options(
          method: :post,
          url: url(neo4j),
          auth: {:basic, "#{neo4j["username"]}:#{neo4j["password"]}"},
          json: %{statement: cypher, parameters: parameters(params)},
          headers: [accept: "application/json"],
          receive_timeout: @timeout
        )

      request |> Req.request() |> answer()
    end
  end

  defp url(neo4j) do
    database =
      case neo4j["database"] do
        value when value in [nil, ""] -> "neo4j"
        value -> value
      end

    "#{String.trim_trailing(neo4j["url"], "/")}/db/#{URI.encode(database, &URI.char_unreserved?/1)}/query/v2"
  end

  defp parameters(params) do
    params
    |> Enum.with_index(1)
    |> Map.new(fn {value, position} -> {"p#{position}", value} end)
  end

  defp answer({:ok, %{status: status, body: %{"data" => data}}}) when status in 200..299 do
    rows = Enum.map(data["values"], &to_row(data["fields"], &1))

    {:ok, %{"rows" => rows, "count" => length(rows)}}
  end

  defp answer({:ok, %{body: %{"errors" => [%{"message" => message} | _rest]}}}) do
    {:error, "Neo4j: #{message}"}
  end

  defp answer({:ok, %{status: status}}), do: {:error, "Neo4j answered #{status}"}

  defp answer({:error, reason}) do
    {:error, "Could not reach Neo4j: #{Exception.message(reason)}"}
  end

  defp to_row(fields, values), do: fields |> Enum.zip(values) |> Map.new()
end
