---
title: Configuração
description: As variáveis de ambiente que o Heddle lê, o que cada uma faz e o padrão.
sidebar:
  order: 4
---

Nada aqui é obrigatório: o Heddle inicia com padrões razoáveis. Numa instalação local, mude com `heddle config set CHAVE=VALOR` e reinicie. Com Docker, coloque no `.env`, ao lado do `docker-compose.yml`. O [`.env.example`](https://github.com/heddlehq/Heddle/blob/main/.env.example) tem todas.

## Servidor

| Variável | Padrão | O que faz |
| --- | --- | --- |
| `PORT` | `4000` | A porta em que o Heddle escuta. |
| `HEDDLE_PORT` | `4000` | Com Docker Compose, a porta publicada na máquina. |
| `PHX_HOST` | | Seu domínio público, só atrás de HTTPS. Liga o redirecionamento para HTTPS, então o proxy precisa mandar `X-Forwarded-Proto`. |
| `SECRET_KEY_BASE` | Gerado | Assina as sessões e criptografa as credenciais. Guarde, faça backup e dê o mesmo a toda interface e worker: mudar perde todas as credenciais. |
| `DATABASE_URL` | | O Postgres a usar, como `ecto://user:pass@host/heddle`. |
| `HEDDLE_UI_MODE` | `full` | `api` serve só a API e os webhooks, sem o editor. |
| `HEDDLE_HOME` | `~/.heddle` | Onde uma instalação local fica. Defina quando sua pasta pessoal tem acento. |
| `HEDDLE_NO_BROWSER` | | Defina para o `heddle start` não abrir o navegador. |

## Banco e workers

| Variável | Padrão | O que faz |
| --- | --- | --- |
| `POOL_SIZE` | `20` | Conexões com o banco, quando a interface e os workers rodam juntos. |
| `UI_POOL_SIZE` | `10` | Conexões com o banco da interface. |
| `WORKER_POOL_SIZE` | `10` | Conexões com o banco de cada worker. |
| `OBAN_EXECUTIONS_CONCURRENCY` | `50` | Quantas execuções um worker roda ao mesmo tempo. |
| `OBAN_DEFAULT_CONCURRENCY` | `2` | Quantas tarefas de fundo, como limpezas, um worker roda ao mesmo tempo. |
| `OBAN_RESCUE_AFTER_MINUTES` | `60` | Quanto tempo uma execução pode durar antes de o Heddle achar que o worker dela morreu e começar de novo. Deixe maior que seu fluxo mais longo. |
| `DNS_CLUSTER_QUERY` | | Um nome DNS que lista as outras máquinas do Heddle, para elas se acharem e formarem um cluster. |

Aumente a concorrência e os pools juntos, dentro do que seu Postgres aguenta. Veja [Escala](/pt/docs/self-hosting/scaling/).

## IA

| Variável | O que faz |
| --- | --- |
| `HEDDLE_LLM_PROVIDER` | O provedor das tarefas de texto quando a página AI não define nenhum: `anthropic`, `openai`, `google` ou `xai`. |
| `HEDDLE_LLM_MODEL` | O modelo dele, como `claude-sonnet-5-5`. |
| `HEDDLE_LLM_API_KEY` | A chave dele. Prefira isso a passar na linha de comando. |
| `HEDDLE_CLAUDE_API_KEY` | A chave do Claude Agent no chat do editor. Pode ficar vazia quando o provedor é `anthropic`. |
| `HEDDLE_CLAUDE_BIN` | Onde está o programa `claude`, quando ele não é encontrado sozinho. |
| `HEDDLE_CLAUDE_MAX_BUDGET_USD` | O máximo que uma rodada do Claude Agent no chat pode gastar, `1` por padrão. |

A página **AI** substitui estas por tipo de tarefa. Veja [Provedores de IA](/pt/docs/guides/ai-providers/).
