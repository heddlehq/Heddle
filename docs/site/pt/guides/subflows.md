---
title: Subfluxos
description: Execute um fluxo a partir de outro, para dividir um fluxo longo ou reaproveitar os mesmos passos em vários.
sidebar:
  order: 3
---

Um nó [Subflow](/pt/docs/nodes/subflow/) executa outro fluxo do workspace como um dos seus passos. Use para dividir um fluxo que cresceu demais, ou para manter num lugar só o que vários fluxos fazem, como pontuar um lead ou avisar o time.

## O fluxo chamado

Comece ele com um [Subflow Trigger](/pt/docs/nodes/subflow-trigger/). Ele recebe o **Data** que o Subflow mandou como `result`, e `caller`, o fluxo que chamou:

```json
{
  "result": {"email": "ana@example.com", "company": "Acme"},
  "caller": {"flow_id": 12, "flow_name": "Novos leads", "execution_id": "8f3k2m"}
}
```

O que ele tiver em `result` quando terminar volta para o fluxo que chamou. Um fluxo sem Subflow Trigger roda a partir do nó Start.

Como tudo que roda sozinho, ele roda a [versão publicada](/pt/docs/concepts/versions/), então publique antes. Cada chamada é uma execução própria, que aparece nas execuções dele com cada passo, e o fluxo de erro dele dispara se ele falhar.

## Chamando

Adicione um nó **Subflow** e escolha o fluxo em **Flow**. **Abrir este fluxo**, logo abaixo, leva até ele. **Data** é um JSON, com placeholders, ou um placeholder só, como `{{result}}`:

```json
{"email": "{{body.email}}", "company": "{{body.company}}"}
```

Depois escolha como ele espera:

- **Wait for it to finish**: a execução segue por `success` com o `result` com que o outro fluxo terminou, ou por `error` com o motivo da falha.
- **Start it and go on**: a execução segue na hora, e `result` é a execução que ele iniciou, como `{"execution_id": "8f3k2m", "flow_id": 12, "flow_name": "Pontuar lead"}`.

Um fluxo que pausa num [Wait](/pt/docs/nodes/wait/) não pode ser esperado: inicie e siga em frente.

## Limites

- Um fluxo só chama fluxos do próprio workspace.
- Um fluxo não pode chamar a si mesmo, direto ou por outros: a chamada sai por `error`.
- Os fluxos se chamam no máximo 8 níveis abaixo.
