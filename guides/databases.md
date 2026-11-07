# Database nodes

The **Database** category reaches the databases your flows use. Each node takes a credential from the **Credentials** page, and answers through its `success` and `error` outputs.

| Nodes | Works on | Credential |
| --- | --- | --- |
| `SQL:` | PostgreSQL, MySQL, MariaDB, SQL Server, Azure SQL, Oracle, SQLite | SQL database |
| `MongoDB:` | MongoDB, Atlas, DocumentDB, Cosmos DB for MongoDB | MongoDB |
| `Redis:` | Redis, Valkey, KeyDB, Dragonfly, Upstash | Redis |
| `Elasticsearch:` | Elasticsearch, OpenSearch | Elasticsearch or OpenSearch |
| `DynamoDB:` | DynamoDB | DynamoDB |
| `Cassandra:` | Cassandra, ScyllaDB | Cassandra or ScyllaDB |
| `Neo4j:` | Neo4j, Aura | Neo4j |

Databases that speak the protocol of another work through its engine. Pick PostgreSQL for CockroachDB, TimescaleDB, Redshift, Neon, Supabase and YugabyteDB, and MySQL for TiDB, PlanetScale and SingleStore. We test on the engines in the first column of the table, so try a compatible one before relying on it.

For anything with an HTTP API that isn't here, like CouchDB, InfluxDB or Firestore, use the **HTTP Request** node.

## Values in a query

A `{{placeholder}}` goes to the database as a parameter, and never becomes part of the query. A value that came from a webhook can't change what the query does:

```sql
SELECT * FROM orders WHERE customer = {{body.customer}} AND status = 'open'
```

- A string that holds a placeholder becomes one parameter: `name LIKE '%{{term}}%'`.
- A placeholder can't name a table or a column. Use the **Table** field of the other nodes, which quotes it.
- Text is converted to the type of the column, so `"42"` from a webhook works on an integer column.

Fields that take JSON work the same way. Outside quotes a placeholder keeps its type, and inside quotes it's written into the text:

```json
{"name": "{{body.name}}", "tags": {{body.tags}}}
```

A field can also be a single placeholder that points at what another node returned, like `{{result.rows}}`.

In a MongoDB filter, a value from the run can't hold an operator, so a request that sends `{"$ne": null}` as a password is refused. A filter that is a single placeholder is yours to check, because the whole filter comes from the run.

## What they return

`SQL: Run Query` and `SQL: Select Rows` return `{{result.rows}}`, a list of objects, and `{{result.count}}`. After an insert, PostgreSQL, SQLite and SQL Server return the new rows, and MySQL returns `{{result.last_id}}`.

Decimal numbers come as text, like `"10.50"`, so they don't lose cents. A run holds up to 10,000 rows or documents, and a query that returns more fails: use a limit.

## Safety

- **Update** and **Delete** refuse an empty **Where** or **Filter**. To hit everything on purpose, write `1 = 1`.
- **Run Transaction** applies all of its statements or none. A transaction can't span several nodes.
- Give an AI Agent that uses these nodes a database user with only the permissions it needs. It writes the fields left blank on a node, the query included.
- SQLite opens a file on the server that runs the flow, so it fits local installs. With several workers, each one sees its own disk.

Connections stay open for five minutes after the last use, with up to five per credential on each worker.
