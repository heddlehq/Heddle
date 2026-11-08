---
title: Triagem de suporte com IA
description: Leia cada chamado novo com IA, decida do que se trata e mande para o canal do time certo.
sidebar:
  order: 3
---

Os chamados chegam do seu help desk por webhook. A IA lê cada um e decide se é sobre cobrança, bug ou vendas, e o Heddle manda para o canal do Slack desse time. O resto vai para o #suporte.

**Você vai usar** [Webhook](/pt/docs/nodes/webhook/), [Respond to Webhook](/pt/docs/nodes/respond-to-webhook/), [AI: Classify](/pt/docs/nodes/ai-classify/), [Switch](/pt/docs/nodes/switch/), [Slack: Send Message](/pt/docs/nodes/slack-send-message/).

<!-- flow:support-triage -->

## Antes de começar

- Um [provedor de IA](/pt/docs/guides/ai-providers/) configurado na página **AI**, para texto.
- Uma credencial do **Slack**, com o bot em quatro canais.

## 1. Receba e confirme

Adicione um **Webhook** com **Method** `POST` e **Path** `/support`. O help desk manda `subject`, `message` e `email`.

Help desks não gostam de esperar, então responda na hora: adicione um **Respond to Webhook** logo depois, com **Status** `202` e **Body** `{"received": true}`. A execução continua depois de responder.

## 2. Classifique o chamado

Ligue um segundo ramo do Webhook num **AI: Classify**:

| Campo | Valor |
| --- | --- |
| Text | `Subject: {{body.subject}}` e, na linha de baixo, `{{body.message}}` |
| Categories | `billing, bug, sales, other` |

Deixe **Credential** e **Model** em branco para usar os padrões da página AI. `result.category` é sempre uma das categorias, exatamente como foi escrita.

## 3. Encaminhe

Adicione um **Switch** na saída `success` do Classify:

| Campo | Valor |
| --- | --- |
| Value | `{{result.category}}` |
| Case 1 | `billing` |
| Case 2 | `bug` |
| Case 3 | `sales` |

## 4. Avise cada time

Adicione um **Slack: Send Message** em cada caso, para o canal daquele time, e um em `otherwise` para o #suporte:

```text
Novo chamado de cobrança de {{body.email}}: {{body.subject}}
```

`body` continua sendo o chamado: Classify e Switch mudaram `result`, não o resto da execução.

Ligue a saída `error` do Classify na mensagem do #suporte também, para o chamado chegar em alguém quando a IA estiver fora.

## 5. Teste

Aperte **Run Flow** e mande:

```json
{"subject": "Cobrado duas vezes", "message": "Meu cartão foi cobrado duas vezes em maio.", "email": "ana@example.com"}
```

O inspetor mostra `{"category": "billing"}` no Classify, o Switch saindo por `case 1` e a mensagem no canal de cobrança. Publique e aponte o webhook do help desk para o endereço do fluxo.

## Indo além

- Deixe um [AI Agent](/pt/docs/guides/ai-agent/) rascunhar uma resposta, com sua documentação ou chamados antigos como ferramentas.
- Tire mais do chamado com [AI: Extract Data](/pt/docs/nodes/ai-extract-data/): o número do pedido, o plano, o quanto o cliente está irritado.
- Traduza os chamados para um idioma antes com [AI: Translate](/pt/docs/nodes/ai-translate/).
