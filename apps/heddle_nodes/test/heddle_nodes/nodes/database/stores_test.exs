defmodule HeddleNodes.Nodes.Database.StoresTest do
  @moduledoc """
  Runs the nodes of each store on a real server, from `docker-compose.databases.yml`.
  """

  use ExUnit.Case, async: false

  alias HeddleNodes.Nodes.{Cassandra, DynamoDB, Elasticsearch, MongoDB, Neo4j, Redis}

  @moduletag :databases
  @moduletag timeout: 30_000

  defmodule Vault do
    def fetch("mongo", "mongodb") do
      {:ok, %{"url" => "mongodb://127.0.0.1:15405/heddle_test", "database" => "heddle_test"}}
    end

    def fetch("redis", "redis"), do: {:ok, %{"url" => "redis://127.0.0.1:15406/1"}}
    def fetch("bad-redis", "redis"), do: {:ok, %{"url" => "redis://:wrong@127.0.0.1:1"}}
    def fetch("es", "elasticsearch"), do: {:ok, %{"url" => "http://127.0.0.1:15408"}}

    def fetch("dynamo", "dynamodb") do
      {:ok,
       %{
         "access_key_id" => "local",
         "secret_access_key" => "local",
         "region" => "us-east-1",
         "endpoint" => "http://127.0.0.1:15409"
       }}
    end

    def fetch("cassandra", "cassandra") do
      {:ok, %{"hosts" => "127.0.0.1:15407", "keyspace" => "", "username" => ""}}
    end

    def fetch("neo4j", "neo4j") do
      {:ok,
       %{"url" => "http://127.0.0.1:15410", "username" => "neo4j", "password" => "heddle-test"}}
    end

    def fetch(name, _kind), do: {:error, "no #{name}"}
  end

  setup do
    client = Application.get_env(:heddle_nodes, :credentials_client)
    plug = Application.get_env(:heddle_nodes, :req_plug)
    Application.put_env(:heddle_nodes, :credentials_client, Vault)
    Application.put_env(:heddle_nodes, :req_plug, nil)

    on_exit(fn ->
      Application.put_env(:heddle_nodes, :credentials_client, client)
      Application.put_env(:heddle_nodes, :req_plug, plug)
    end)
  end

  defp node_run(module, credential, controls, context \\ %{}) do
    context = context |> Map.merge(controls) |> Map.put("credential", credential)

    case module.handler(context, nil) do
      {:ok, %{"result" => %{"error" => message}}, "error"} -> {:error, message}
      {:ok, %{"result" => result}, "success"} -> {:ok, result}
    end
  end

  describe "MongoDB" do
    setup do
      collection = "items_#{System.system_time(:microsecond)}"

      {:ok, %{"count" => 3}} =
        node_run(MongoDB.InsertDocuments, "mongo", %{
          "collection" => collection,
          "documents" =>
            ~s([{"name": "a", "n": 1}, {"name": "b", "n": 2}, {"name": "c", "n": 3, "at": {"$date": "2026-11-07T10:00:00Z"}}])
        })

      %{collection: collection}
    end

    test "finds with a filter, fields, sort, limit and skip", %{collection: collection} do
      assert {:ok, %{"documents" => [%{"name" => "b"} = document], "count" => 1}} =
               node_run(
                 MongoDB.FindDocuments,
                 "mongo",
                 %{
                   "collection" => collection,
                   "filter" => ~s({"n": {"$gte": {{min}}}}),
                   "fields" => ~s({"name": 1}),
                   "sort" => ~s({"n": -1}),
                   "limit" => "1",
                   "offset" => "1"
                 },
                 %{"min" => 2}
               )

      assert is_binary(document["_id"])
      refute Map.has_key?(document, "n")
    end

    test "returns dates and ids a run can keep", %{collection: collection} do
      assert {:ok, %{"documents" => [document]}} =
               node_run(MongoDB.FindDocuments, "mongo", %{
                 "collection" => collection,
                 "filter" => ~s({"name": "c"})
               })

      assert document["at"] == "2026-11-07T10:00:00.000Z"
      assert Jason.encode!(document)

      assert {:ok, %{"documents" => [%{"name" => "c"}]}} =
               node_run(
                 MongoDB.FindDocuments,
                 "mongo",
                 %{"collection" => collection, "filter" => ~s({"_id": "{{id}}"})},
                 %{"id" => document["_id"]}
               )
    end

    test "a value from a run can't become an operator", %{collection: collection} do
      assert {:error, message} =
               node_run(
                 MongoDB.FindDocuments,
                 "mongo",
                 %{"collection" => collection, "filter" => ~s({"name": {{name}}})},
                 %{"name" => %{"$ne" => nil}}
               )

      assert message =~ "operator"
    end

    test "updates what matches, and refuses an empty filter", %{collection: collection} do
      assert {:ok, %{"matched" => 2, "modified" => 2}} =
               node_run(MongoDB.UpdateDocuments, "mongo", %{
                 "collection" => collection,
                 "filter" => ~s({"n": {"$gt": 1}}),
                 "update" => ~s({"$set": {"seen": true}})
               })

      assert {:ok, %{"matched" => 1, "modified" => 1}} =
               node_run(MongoDB.UpdateDocuments, "mongo", %{
                 "collection" => collection,
                 "filter" => ~s({"n": {"$gt": 1}}),
                 "update" => ~s({"$set": {"seen": false}}),
                 "which" => "first"
               })

      assert {:ok, %{"upserted_ids" => [_id]}} =
               node_run(MongoDB.UpdateDocuments, "mongo", %{
                 "collection" => collection,
                 "filter" => ~s({"name": "new"}),
                 "update" => ~s({"$set": {"n": 9}}),
                 "upsert" => "yes"
               })

      assert {:error, _message} =
               node_run(MongoDB.UpdateDocuments, "mongo", %{
                 "collection" => collection,
                 "filter" => "",
                 "update" => ~s({"$set": {"n": 0}})
               })
    end

    test "counts, aggregates, lists and deletes", %{collection: collection} do
      assert {:ok, %{"count" => 2}} =
               node_run(MongoDB.CountDocuments, "mongo", %{
                 "collection" => collection,
                 "filter" => ~s({"n": {"$lt": 3}})
               })

      assert {:ok, %{"documents" => [%{"_id" => nil, "total" => 6}]}} =
               node_run(MongoDB.Aggregate, "mongo", %{
                 "collection" => collection,
                 "pipeline" => ~s([{"$group": {"_id": null, "total": {"$sum": "$n"}}}])
               })

      assert {:ok, %{"collections" => collections}} =
               node_run(MongoDB.ListCollections, "mongo", %{})

      assert collection in collections

      assert {:error, _message} =
               node_run(MongoDB.DeleteDocuments, "mongo", %{
                 "collection" => collection,
                 "filter" => ""
               })

      assert {:ok, %{"count" => 1}} =
               node_run(MongoDB.DeleteDocuments, "mongo", %{
                 "collection" => collection,
                 "filter" => ~s({"name": "a"})
               })
    end
  end

  describe "Redis" do
    setup do
      %{key: "heddle:test:#{System.system_time(:microsecond)}"}
    end

    test "sets, gets, expires and deletes", %{key: key} do
      assert {:ok, _result} =
               node_run(Redis.SetValue, "redis", %{"key" => key, "value" => "hello {{who}}"}, %{
                 "who" => "you"
               })

      assert {:ok, %{"value" => "hello you", "found" => true}} =
               node_run(Redis.GetValue, "redis", %{"key" => key})

      assert {:ok, %{"count" => 1}} = node_run(Redis.DeleteKeys, "redis", %{"keys" => key})
      assert {:ok, %{"found" => false}} = node_run(Redis.GetValue, "redis", %{"key" => key})

      assert {:ok, _result} =
               node_run(Redis.SetValue, "redis", %{
                 "key" => key,
                 "value" => "x",
                 "seconds" => "100"
               })

      assert {:ok, %{"reply" => ttl}} =
               node_run(Redis.RunCommand, "redis", %{"command" => ~s(["TTL", "#{key}"])})

      assert ttl in 90..100
    end

    test "increments", %{key: key} do
      assert {:ok, %{"value" => 1}} = node_run(Redis.Increment, "redis", %{"key" => key})

      assert {:ok, %{"value" => 6}} =
               node_run(Redis.Increment, "redis", %{"key" => key, "amount" => "5"})
    end

    test "finds keys", %{key: key} do
      node_run(Redis.SetValue, "redis", %{"key" => key, "value" => "x"})

      assert {:ok, %{"keys" => [^key]}} =
               node_run(Redis.FindKeys, "redis", %{"pattern" => key <> "*"})
    end

    test "writes and reads hashes and lists", %{key: key} do
      assert {:ok, %{"added" => 2}} =
               node_run(Redis.WriteHash, "redis", %{
                 "key" => key,
                 "fields" => ~s({"name": "a", "age": 30})
               })

      assert {:ok, %{"fields" => %{"name" => "a", "age" => "30"}}} =
               node_run(Redis.ReadHash, "redis", %{"key" => key})

      list = key <> ":list"
      node_run(Redis.PushToList, "redis", %{"key" => list, "value" => "b"})
      node_run(Redis.PushToList, "redis", %{"key" => list, "value" => "a", "side" => "start"})

      assert {:ok, %{"items" => ["a", "b"], "count" => 2}} =
               node_run(Redis.ReadList, "redis", %{"key" => list})
    end

    test "publishes" do
      assert {:ok, %{"subscribers" => 0}} =
               node_run(Redis.PublishMessage, "redis", %{"channel" => "c", "value" => "m"})
    end

    test "runs a command with values as arguments" do
      assert {:ok, %{"reply" => "a b"}} =
               node_run(Redis.RunCommand, "redis", %{"command" => ~s(["ECHO", {{text}}])}, %{
                 "text" => "a b"
               })

      assert {:error, message} =
               node_run(Redis.RunCommand, "redis", %{"command" => ~s(["NOPE"])})

      assert message =~ "unknown command"
    end

    test "says when it can't connect" do
      assert {:error, message} = node_run(Redis.GetValue, "bad-redis", %{"key" => "x"})
      assert message =~ "Could not connect"
      refute message =~ "wrong"
    end
  end

  describe "Elasticsearch" do
    setup do
      index = "items_#{System.system_time(:microsecond)}"
      on_exit(fn -> Req.delete("http://127.0.0.1:15408/#{index}") end)

      %{index: index}
    end

    test "indexes, reads, updates, searches and deletes", %{index: index} do
      assert {:ok, %{"id" => "1", "outcome" => "created"}} =
               node_run(
                 Elasticsearch.IndexDocument,
                 "es",
                 %{
                   "index_name" => index,
                   "document_id" => "1",
                   "document" => ~s({"title": "hello world", "n": {{n}}})
                 },
                 %{"n" => 1}
               )

      assert {:ok, %{"id" => generated}} =
               node_run(Elasticsearch.IndexDocument, "es", %{
                 "index_name" => index,
                 "document" => ~s({"title": "other"})
               })

      assert is_binary(generated)

      assert {:ok, %{"title" => "hello world", "_id" => "1"}} =
               node_run(Elasticsearch.GetDocument, "es", %{
                 "index_name" => index,
                 "document_id" => "1"
               })

      assert {:ok, %{"outcome" => "updated"}} =
               node_run(Elasticsearch.UpdateDocument, "es", %{
                 "index_name" => index,
                 "document_id" => "1",
                 "changes" => ~s({"n": 2})
               })

      assert {:ok, _result} =
               node_run(Elasticsearch.RunRequest, "es", %{
                 "method" => "POST",
                 "path" => "/#{index}/_refresh"
               })

      assert {:ok, %{"total" => 1, "documents" => [%{"_id" => "1", "n" => 2}]}} =
               node_run(
                 Elasticsearch.Search,
                 "es",
                 %{"index_name" => index, "search" => ~s({"match": {"title": "{{term}}"}})},
                 %{"term" => "hello"}
               )

      assert {:ok, %{"outcome" => "deleted"}} =
               node_run(Elasticsearch.DeleteDocument, "es", %{
                 "index_name" => index,
                 "document_id" => "1"
               })

      assert {:error, message} =
               node_run(Elasticsearch.GetDocument, "es", %{
                 "index_name" => index,
                 "document_id" => "1"
               })

      assert message =~ "404"
    end
  end

  describe "DynamoDB" do
    setup do
      table = "items_#{System.system_time(:microsecond)}"

      {:ok, _response} =
        Req.post("http://127.0.0.1:15409/",
          headers: [
            {"x-amz-target", "DynamoDB_20120810.CreateTable"},
            {"content-type", "application/x-amz-json-1.0"}
          ],
          aws_sigv4: [
            access_key_id: "local",
            secret_access_key: "local",
            region: "us-east-1",
            service: :dynamodb
          ],
          body:
            Jason.encode!(%{
              TableName: table,
              BillingMode: "PAY_PER_REQUEST",
              AttributeDefinitions: [
                %{AttributeName: "pk", AttributeType: "S"},
                %{AttributeName: "sk", AttributeType: "N"}
              ],
              KeySchema: [
                %{AttributeName: "pk", KeyType: "HASH"},
                %{AttributeName: "sk", KeyType: "RANGE"}
              ]
            })
        )

      %{table: table}
    end

    test "puts, reads, updates, queries, scans and deletes", %{table: table} do
      item =
        ~s({"pk": "a", "sk": 1, "name": "x", "tags": ["t"], "more": {"ok": true}, "price": 1.5})

      key = ~s({"pk": "a", "sk": 1})

      assert {:ok, %{"saved" => true}} =
               node_run(DynamoDB.PutItem, "dynamo", %{"table" => table, "item_data" => item})

      assert {:ok, %{"found" => true, "item" => found}} =
               node_run(DynamoDB.GetItem, "dynamo", %{"table" => table, "item_key" => key})

      assert found == %{
               "pk" => "a",
               "sk" => 1,
               "name" => "x",
               "tags" => ["t"],
               "more" => %{"ok" => true},
               "price" => 1.5
             }

      assert {:ok, %{"item" => %{"name" => "y", "sk" => 1}}} =
               node_run(DynamoDB.UpdateItem, "dynamo", %{
                 "table" => table,
                 "item_key" => key,
                 "changes" => ~s({"name": "y"})
               })

      assert {:ok, %{"count" => 1, "items" => [%{"name" => "y"}]}} =
               node_run(
                 DynamoDB.QueryItems,
                 "dynamo",
                 %{
                   "table" => table,
                   "condition" => "pk = :pk",
                   "condition_values" => ~s({":pk": "{{id}}"})
                 },
                 %{"id" => "a"}
               )

      assert {:ok, %{"count" => 1}} = node_run(DynamoDB.ScanItems, "dynamo", %{"table" => table})

      assert {:ok, %{"tables" => tables}} = node_run(DynamoDB.ListTables, "dynamo", %{})
      assert table in tables

      assert {:ok, %{"deleted" => true}} =
               node_run(DynamoDB.DeleteItem, "dynamo", %{"table" => table, "item_key" => key})

      assert {:ok, %{"found" => false}} =
               node_run(DynamoDB.GetItem, "dynamo", %{"table" => table, "item_key" => key})
    end

    test "reports what the service refuses" do
      assert {:error, message} =
               node_run(DynamoDB.ScanItems, "dynamo", %{"table" => "nowhere"})

      assert message =~ "400"
    end
  end

  describe "Cassandra" do
    test "creates, writes and reads, with values as parameters" do
      query = fn cql, context ->
        node_run(Cassandra.RunQuery, "cassandra", %{"cql" => cql}, context)
      end

      table = "heddle_test.items_#{System.system_time(:microsecond)}"

      assert {:ok, _result} =
               query.(
                 "CREATE KEYSPACE IF NOT EXISTS heddle_test WITH replication = " <>
                   "{'class': 'SimpleStrategy', 'replication_factor': 1}",
                 %{}
               )

      assert {:ok, _result} =
               query.(
                 "CREATE TABLE #{table} (id int PRIMARY KEY, name text, price decimal, " <>
                   "at timestamp, active boolean, ref uuid, tags set<text>)",
                 %{}
               )

      assert {:ok, %{"count" => 0}} =
               query.(
                 "INSERT INTO #{table} (id, name, price, at, active, ref, tags) " <>
                   "VALUES ({{id}}, {{name}}, {{price}}, {{at}}, {{active}}, {{ref}}, {{tags}})",
                 %{
                   "id" => "7",
                   "name" => "o'brien",
                   "price" => "10.50",
                   "at" => "2026-11-07T10:00:00Z",
                   "active" => "true",
                   "ref" => "6f9619ff-8b86-d011-b42d-00c04fc964ff",
                   "tags" => ["a"]
                 }
               )

      assert {:ok, %{"count" => 1, "rows" => [row]}} =
               query.("SELECT * FROM #{table} WHERE id = {{id}}", %{"id" => 7})

      assert %{
               "id" => 7,
               "name" => "o'brien",
               "price" => "10.50",
               "active" => true,
               "ref" => "6f9619ff-8b86-d011-b42d-00c04fc964ff"
             } = row

      assert Jason.encode!(row)
    end

    test "reports what the server refuses" do
      assert {:error, _message} =
               node_run(Cassandra.RunQuery, "cassandra", %{"cql" => "SELECT * FROM nowhere.t"})
    end
  end

  describe "Neo4j" do
    test "runs Cypher, with values as parameters" do
      label = "Item#{System.system_time(:microsecond)}"

      assert {:ok, %{"count" => 1, "rows" => [%{"name" => "o'brien"}]}} =
               node_run(
                 Neo4j.RunQuery,
                 "neo4j",
                 %{"cypher" => "CREATE (n:#{label} {name: {{name}}}) RETURN n.name AS name"},
                 %{"name" => "o'brien"}
               )

      assert {:ok, %{"count" => 1}} =
               node_run(
                 Neo4j.RunQuery,
                 "neo4j",
                 %{"cypher" => "MATCH (n:#{label}) WHERE n.name CONTAINS '{{part}}' RETURN n"},
                 %{"part" => "brien"}
               )

      assert {:error, message} = node_run(Neo4j.RunQuery, "neo4j", %{"cypher" => "NOT CYPHER"})
      assert message =~ "Neo4j"
    end
  end
end
