---
title: Bancos de dados
description: Acesse PostgreSQL, MySQL, SQL Server, Oracle, SQLite, MongoDB, Redis, Elasticsearch, DynamoDB, Cassandra e Neo4j com segurança.
sidebar:
  order: 3
---

A categoria **Database** acessa os bancos que seus fluxos usam. Cada nó usa uma credencial da página **Credentials** e responde pelas saídas `success` e `error`.

| Nós | Funciona com | Credencial |
| --- | --- | --- |
| `SQL:` | PostgreSQL, MySQL, MariaDB, SQL Server, Azure SQL, Oracle, SQLite | SQL database |
| `MongoDB:` | MongoDB, Atlas, DocumentDB, Cosmos DB for MongoDB | MongoDB |
| `Redis:` | Redis, Valkey, KeyDB, Dragonfly, Upstash | Redis |
| `Elasticsearch:` | Elasticsearch, OpenSearch | Elasticsearch or OpenSearch |
| `DynamoDB:` | DynamoDB | DynamoDB |
| `Cassandra:` | Cassandra, ScyllaDB | Cassandra or ScyllaDB |
| `Neo4j:` | Neo4j, Aura | Neo4j |

Bancos que falam o protocolo de outro funcionam pelo motor dele. Escolha PostgreSQL para CockroachDB, TimescaleDB, Redshift, Neon, Supabase e YugabyteDB, e MySQL para TiDB, PlanetScale e SingleStore. Testamos nos motores da primeira coluna da tabela, então teste um compatível antes de depender dele.

Para qualquer coisa com uma API HTTP que não está aqui, como CouchDB, InfluxDB ou Firestore, use o nó **HTTP Request**.

## Valores numa consulta

Um `{{placeholder}}` vai para o banco como parâmetro, e nunca vira parte da consulta. Um valor que veio de um webhook não muda o que a consulta faz:

```sql
SELECT * FROM orders WHERE customer = {{body.customer}} AND status = 'open'
```

- Um texto entre aspas com um placeholder vira um parâmetro: `name LIKE '%{{termo}}%'`.
- Um placeholder não pode dar nome a uma tabela ou coluna. Use o campo **Table** dos outros nós, que coloca as aspas certas.
- Texto é convertido para o tipo da coluna, então `"42"` vindo de um webhook funciona numa coluna inteira.

Campos que recebem JSON funcionam igual. Fora de aspas, o placeholder mantém o tipo, e dentro de aspas é escrito no texto:

```json
{"name": "{{body.name}}", "tags": {{body.tags}}}
```

Um campo também pode ser um único placeholder que aponta para o que outro nó devolveu, como `{{result.rows}}`.

Num filtro do MongoDB, um valor da execução não pode conter um operador, então um pedido que manda `{"$ne": null}` como senha é recusado. Um filtro que é um único placeholder é responsabilidade sua, porque o filtro inteiro vem da execução.

## O que devolvem

`SQL: Run Query` e `SQL: Select Rows` devolvem `{{result.rows}}`, uma lista de objetos, e `{{result.count}}`. Depois de um insert, PostgreSQL, SQLite e SQL Server devolvem as linhas novas, e o MySQL devolve `{{result.last_id}}`.

Números decimais vêm como texto, como `"10.50"`, para não perder centavos. Uma execução guarda até 10.000 linhas ou documentos, e uma consulta que devolve mais falha: use um limite.

Cada nó tem a sua página na [referência de nós](/pt/docs/nodes/#database), com um exemplo do que devolve.

## Segurança

- **Update** e **Delete** recusam um **Where** ou **Filter** vazio. Para atingir tudo de propósito, escreva `1 = 1`.
- **Run Transaction** aplica todos os comandos ou nenhum. Uma transação não atravessa vários nós.
- Dê a um AI Agent que usa estes nós um usuário de banco só com as permissões necessárias. Ele escreve os campos deixados em branco num nó, inclusive a consulta.
- O SQLite abre um arquivo no servidor que roda o fluxo, então serve para instalações locais. Com vários workers, cada um vê o próprio disco.

As conexões ficam abertas por cinco minutos depois do último uso, com até cinco por credencial em cada worker.

## Testes

Para quem desenvolve o Heddle: `docker compose -f docker-compose.databases.yml up -d --wait`, depois `HEDDLE_DB_PORT=5436 mix test --include databases`. Sem eles, só SQLite e PostgreSQL rodam num servidor de verdade.
