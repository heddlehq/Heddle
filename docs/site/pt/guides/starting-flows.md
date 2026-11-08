---
title: Disparando fluxos
description: Rode um fluxo por webhook, num horário, pela API ou quando outro fluxo falha.
sidebar:
  order: 2
---

**Run Flow** no editor é para testar. Em produção, os fluxos começam sozinhos: por um webhook, num horário, pela API ou quando outro fluxo falha. Todos esses rodam a [versão publicada](/pt/docs/concepts/versions/), então publique antes.

## Webhooks

Adicione um nó [Webhook](/pt/docs/nodes/webhook/), escolha o **Method** e dê um **Path**. O endereço dele é:

```text
https://seu-heddle/api/flows/<id do fluxo>/webhook/<caminho>
```

O id do fluxo está na URL do editor. Uma chamada com outro método, ou para um fluxo que não está publicado, recebe `404`.

O que a requisição traz fica na execução como `body`, `headers`, `query_params`, `method` e `request_path`:

```bash
curl -X POST https://seu-heddle/api/flows/12/webhook/leads \
  -H "Content-Type: application/json" \
  -d '{"name": "Ana", "email": "ana@example.com"}'
```

Aí `{{body.email}}` é `ana@example.com`.

### Respondendo a quem chamou

Por padrão, quem chama recebe uma resposta na hora, e a execução segue sozinha:

```json
{"status": "accepted", "execution_id": "8f3k2m", "execution_status": "queued"}
```

Para responder com o que o fluxo encontrou, adicione um [Respond to Webhook](/pt/docs/nodes/respond-to-webhook/). Quem chamou espera por ele, até 30 segundos, e recebe o **Status** e o **Body** dele. Os passos depois dele continuam rodando. Uma execução que falha antes de responder devolve `500`, e uma que demora demais devolve `504`.

### Conferindo quem chama

O endereço de um webhook é público. Para aceitar só as chamadas que você espera, peça a quem chama um segredo, e confira primeiro com um [Switch](/pt/docs/nodes/switch/):

| Campo | Valor |
| --- | --- |
| Value | `{{headers.x-webhook-secret}}` |
| Case 1 | o segredo |

Ligue o resto do fluxo em `case 1`, e um **Respond to Webhook** com status `401` em `otherwise`.

## Agendamentos

Um [Schedule](/pt/docs/nodes/schedule/) inicia o fluxo nos horários da expressão cron dele, em UTC.

| Cron | Roda |
| --- | --- |
| `0 9 * * *` | Todo dia às 09:00 UTC |
| `0 12 * * 1-5` | Ao meio-dia UTC nos dias úteis |
| `*/15 * * * *` | A cada 15 minutos |
| `0 8 1 * *` | No dia 1º de cada mês às 08:00 UTC |

São Paulo está em UTC−3, então 09:00 lá é `0 12 * * *`. Um fluxo pode ter vários Schedules.

## A API

Com uma [chave de API](/pt/docs/reference/api/#autenticação), coloque uma execução na fila:

```bash
curl -X POST https://seu-heddle/api/v1/workflows/12/executions \
  -H "Authorization: Bearer $HEDDLE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"input": {"variables": {"customer_id": 42}}}'
```

Ela responde na hora com o id da execução, e `GET /api/v1/workflows/12/executions/<id>` lê como foi. Mande `"version": "draft"` no corpo para rodar o rascunho em vez da versão publicada. Um fluxo que nunca foi publicado responde `409`. Veja a [referência da API](/pt/docs/reference/api/).

## Quando outro fluxo falha

Um fluxo que começa com um [Error Trigger](/pt/docs/nodes/error-trigger/) roda quando falha um fluxo que escolheu ele como fluxo de erro. Veja [Fluxos de erro](/pt/docs/guides/error-handling/#fluxos-de-erro).

## Esperando uma chamada no meio da execução

Um [Wait](/pt/docs/nodes/wait/) em **Until a call** pausa a execução até alguém chamar `{{resume_url}}`. Mande esse endereço num email, numa mensagem do Slack ou para uma API, e a execução continua quando ele for chamado, com a requisição em `result`. O [tutorial de reembolso com aprovação](/pt/docs/tutorials/refund-approval/) faz isso.
