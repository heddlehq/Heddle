---
title: Escala
description: Rode a interface e os workers separados, e dimensione os dois para a carga.
sidebar:
  order: 1
---

Este guia mostra como escalar o **Heddle**, que separa a interface dos workers.

## Como roda

O Heddle tem dois papéis:

- `heddle_ui`: serve o Phoenix, o LiveView e o HTTP, e coloca as execuções na fila;
- `heddle_worker`: consome os jobs do Oban e roda os fluxos.

Por isso, escalar costuma ser:

- manter poucas instâncias da interface;
- aumentar o número de workers conforme o volume de execuções.

Por exemplo, para **1 servidor e 5 workers**, você roda:

- 1 `ui`;
- 5 `worker`;
- 1 Postgres compartilhado.

## Uma regra importante

Todas as instâncias de interface e de worker precisam apontar para o mesmo banco, porque o Oban usa o Postgres como fila.

No mínimo, toda instância precisa de:

- `DATABASE_URL`;
- `SECRET_KEY_BASE`;
- `HEDDLE_LLM_PROVIDER`, `HEDDLE_LLM_MODEL` e `HEDDLE_LLM_API_KEY` para ligar os chats de IA (`OPENAI_API_KEY` ainda funciona quando o provedor não está definido);
- `HEDDLE_CLAUDE_API_KEY` nas instâncias de interface para usar o Claude Agent, que também precisa do programa `claude` lá: gere a imagem com `--build-arg INSTALL_CLAUDE=true`.

## Docker Compose

É o jeito mais simples de rodar **1 interface e 5 workers** localmente ou numa máquina só.

```bash
docker compose up -d --build db ui
docker compose up -d --scale worker=5 worker
```

Ou num comando só:

```bash
docker compose up -d --build db ui --scale worker=5 worker
```

Confira os containers com `docker compose ps`. Você deve ver `db`, `ui` e `worker-1` a `worker-5`.

## Docker run

Sem Compose, gere a imagem uma vez:

```bash
docker build -t heddle .
```

Rode a interface:

```bash
docker run -d --name heddle-ui -p 4000:4000 \
  --env-file .env \
  -e DATABASE_URL=ecto://postgres:postgres@host.docker.internal/heddle \
  -v heddle_data:/app/data \
  heddle ui
```

Rode os workers:

```bash
docker run -d --name heddle-worker-1 \
  --env-file .env \
  -e DATABASE_URL=ecto://postgres:postgres@host.docker.internal/heddle \
  heddle worker
```

Repita para `heddle-worker-2` até `heddle-worker-5`. A imagem é a mesma; muda só o modo do container: `heddle ui` ou `heddle worker`.

## Releases separados, sem Docker

Para máquinas virtuais ou servidores físicos, gere os dois releases:

```bash
mix release heddle_ui
mix release heddle_worker
```

Na máquina da interface:

```bash
_build/prod/rel/heddle_ui/bin/heddle_ui start
```

Em cada máquina de worker:

```bash
_build/prod/rel/heddle_worker/bin/heddle_worker start
```

## Planejando capacidade

Escalar workers não é só "adicionar containers". Você também precisa olhar o banco e a concorrência da fila.

A configuração padrão de cada worker:

- `WORKER_POOL_SIZE=10`;
- fila `executions` com 50;
- fila `default` com 2.

Então cada worker roda até cerca de 50 execuções ao mesmo tempo, e com **5 workers** a fila `executions` chega a umas **250 execuções simultâneas**.

Quase todo o tempo de uma execução é esperando outros serviços, e uma execução esperando não segura conexão com o banco, então a fila pode ser bem maior que o pool. Diminua se seus fluxos usam muita CPU ou memória, ou se os serviços que eles chamam não aguentam tantas chamadas ao mesmo tempo.

Antes de escalar, revise:

- o `POOL_SIZE` do banco;
- o limite de conexões do Postgres;
- a CPU e a memória de cada worker;
- o que cada fluxo usa para rodar.

Se você escala os workers e mantém um pool pequeno, o gargalo só muda para o Postgres.

## Ajustes

As principais variáveis para mudar ao escalar:

- `UI_POOL_SIZE`;
- `WORKER_POOL_SIZE`;
- `OBAN_EXECUTIONS_CONCURRENCY`;
- `OBAN_DEFAULT_CONCURRENCY`.

Um perfil de worker mais conservador:

```bash
WORKER_POOL_SIZE=2
OBAN_EXECUTIONS_CONCURRENCY=4
OBAN_DEFAULT_CONCURRENCY=1
```

## Topologia recomendada

Para a maioria das instalações:

1. Rode a interface e o worker como serviços separados.
2. Mantenha o Postgres fora deles e persistente.
3. Escale os workers primeiro, na horizontal.
4. Escale a interface só quando o tráfego de HTTP ou LiveView pedir.

Exemplos comuns:

- pouco tráfego: `1 ui`, `1 worker`;
- tráfego moderado: `1 ui`, `3 workers`;
- muita carga assíncrona: `2 ui`, `5 workers`.

## Notas de operação

- As migrations rodam uma vez por deploy, não uma por réplica de worker.
- Com várias instâncias de interface, coloque um balanceador de carga na frente.
- Os workers não precisam da porta `4000`.
- Se um worker morre, o Oban recupera os jobs pela lógica de retentativa e resgate.

## Receitas rápidas

### 1 interface e 5 workers com Compose

```bash
docker compose up -d --build db ui --scale worker=5 worker
```

### 2 interfaces e 10 workers com Compose

```bash
docker compose up -d --build db --scale ui=2 --scale worker=10 ui worker
```

### Só mais workers

Se a interface já está rodando e as execuções estão acumulando:

```bash
docker compose up -d --scale worker=8 worker
```
