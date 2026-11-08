---
title: Reembolsos com aprovação
description: Pause uma execução até alguém aprovar no Slack, aí reembolse por uma API, ou desista depois de um dia.
sidebar:
  order: 4
---

Chega um pedido de reembolso. O Heddle pergunta ao #financeiro no Slack, com um link para aprovar e um para recusar, e espera. Quando alguém clica, a execução continua: chama a API de pagamentos ou avisa que foi recusado. Se ninguém decidir em 24 horas, ele avisa.

**Você vai usar** [Webhook](/pt/docs/nodes/webhook/), [Slack: Send Message](/pt/docs/nodes/slack-send-message/), [Wait](/pt/docs/nodes/wait/), [Switch](/pt/docs/nodes/switch/), [HTTP Request](/pt/docs/nodes/http-request/). **Importe:** [refund-approval.json](/docs/examples/refund-approval.json).

## 1. Receba o pedido

Adicione um **Webhook** com **Method** `POST` e **Path** `/refunds`. Ele recebe `order_id`, `amount` e `reason`.

## 2. Peça uma decisão

Adicione um **Slack: Send Message** para o #financeiro:

```text
Reembolso de {{body.amount}} do pedido {{body.order_id}} ({{body.reason}}).
Aprovar: {{resume_url}}?decision=approve
Recusar: {{resume_url}}?decision=reject
```

`{{resume_url}}` é um endereço feito para esta execução, que existe porque o fluxo tem um Wait. Chamar ele, nem que seja clicando num link, faz a execução continuar.

## 3. Espere

Adicione um **Wait** na saída `success` do Slack:

| Campo | Valor |
| --- | --- |
| Wait | Until a call |
| How long | `24` |
| Unit | `hours` |

A execução é salva e para aqui, sem ocupar nenhum worker. Ela sobrevive a reinícios. Quando o endereço é chamado, ela segue por `exec`, com a requisição em `result`. Depois de 24 horas sem chamada, segue por `timeout`.

## 4. Aja conforme a decisão

Adicione um **Switch** em `exec`, com **Value** `{{result.query_params.decision}}`, **Case 1** `approve` e **Case 2** `reject`.

Em `case 1`, um **HTTP Request** para a sua API de pagamentos:

| Campo | Valor |
| --- | --- |
| Method | `POST` |
| Endpoint URL | `https://payments.example.com/refunds` |
| Headers (JSON) | `{"Content-Type": "application/json"}` |
| Body | `{"order_id": "{{body.order_id}}", "amount": {{body.amount}}}` |

Depois, uma mensagem no Slack dizendo que foi reembolsado. Em `case 2`, uma dizendo que foi recusado, e no `timeout` do Wait, uma dizendo que ninguém decidiu.

## 5. Teste

Aperte **Run Flow** com:

```json
{"order_id": "4411", "amount": 129.9, "reason": "Chegou quebrado"}
```

O inspetor mostra a execução **Waiting** no Wait. Clique em **Aprovar** no Slack: o navegador mostra `{"status": "resumed"}`, e a execução termina pelo reembolso. Um segundo clique responde que ela já foi retomada.

## Indo além

- Qualquer um com o link decide. Para saber quem foi, mande os links numa mensagem direta, ou peça um código no corpo e confira.
- Pergunte por email, com [Email: Send Email](/pt/docs/nodes/email-send-email/).
- Espere até uma data, como o fim de um período de teste, com **Until a date**.
