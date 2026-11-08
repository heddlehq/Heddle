---
title: Webhook para o Slack
description: Receba leads do formulário do site, avise o time de vendas no Slack e responda ao formulário se deu certo.
sidebar:
  order: 1
---

Um formulário no seu site manda cada lead novo para o Heddle. O Heddle avisa o **#vendas** no Slack e responde ao formulário, que pode mostrar "obrigado" ou um erro.

**Você vai usar** [Webhook](/pt/docs/nodes/webhook/), [Slack: Send Message](/pt/docs/nodes/slack-send-message/), [Respond to Webhook](/pt/docs/nodes/respond-to-webhook/). **Importe:** [webhook-to-slack.json](/docs/examples/webhook-to-slack.json).

## Antes de começar

Crie uma credencial do **Slack** com um bot que tenha `chat:write`, e convide ele para o canal. Veja [Credenciais](/pt/docs/guides/credentials/#slack).

## 1. Receba o formulário

Crie um fluxo chamado `Novos leads no Slack` e adicione um **Webhook**:

| Campo | Valor |
| --- | --- |
| Method | `POST` |
| Path | `/leads` |

O endereço dele é `https://seu-heddle/api/flows/<id do fluxo>/webhook/leads`, e o id do fluxo é o número na URL do editor.

## 2. Avise o time

Adicione um **Slack: Send Message** depois do Webhook:

| Campo | Valor |
| --- | --- |
| Credential | Sua credencial do Slack |
| Channel | O ID do #vendas, como `C0123456789` |
| Message | `Novo lead: *{{body.name}}* <{{body.email}}> da {{body.company}}` |

`{{body.name}}` lê o `name` que o formulário mandou. Veja [Dados numa execução](/pt/docs/concepts/context/).

## 3. Responda ao formulário

O formulário espera uma resposta, então dê uma nos dois casos:

1. Adicione um **Respond to Webhook** na saída `success` do Slack, com **Status** `200` e **Body** `{"ok": true}`.
2. Adicione outro na saída `error`, com **Status** `502` e **Body** `{"ok": false, "error": "{{result.error}}"}`.

Como a saída de erro está conectada, uma falha do Slack não derruba a execução: ela responde ao formulário.

## 4. Teste

Aperte **Run Flow**. Um fluxo que começa num Webhook pede a requisição para testar. Mande um corpo JSON:

```json
{"name": "Ana Souza", "email": "ana@example.com", "company": "Acme"}
```

A mensagem aparece no #vendas, e o inspetor mostra o que o fluxo teria respondido.

## 5. Coloque no ar

Aperte **Publish**. A partir de agora, as chamadas chegam na versão publicada:

```bash
curl -X POST https://seu-heddle/api/flows/12/webhook/leads \
  -H "Content-Type: application/json" \
  -d '{"name": "Ana Souza", "email": "ana@example.com", "company": "Acme"}'
```

```json
{"ok": true}
```

## Indo além

- Guarde cada lead também: um [SQL: Insert Rows](/pt/docs/nodes/sql-insert-rows/) ou [Google Sheets: Add Rows](/pt/docs/nodes/google-sheets-add-rows/) antes do Slack.
- Aceite só o seu formulário: [confira um cabeçalho secreto](/pt/docs/guides/starting-flows/#conferindo-quem-chama).
- Saiba quando quebrar: adicione um [fluxo de erro](/pt/docs/guides/error-handling/#fluxos-de-erro).
