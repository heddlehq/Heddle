---
title: Dados numa execução
description: O contexto que cada passo lê e aumenta, o result, as variáveis, e como os {{placeholders}} leem tudo isso.
sidebar:
  order: 1
---

Uma execução carrega um objeto do primeiro passo até o último: o **contexto**. Cada passo lê ele e deixa ele mudado para o próximo. Saber o que está ali é quase tudo que você precisa para montar um fluxo.

## Com o que a execução começa

| Iniciada por | O contexto começa com |
| --- | --- |
| **Run Flow** no editor, ou a API | O que foi mandado como `input`. Pela API, `{"input": {"variables": {"user_id": 42}}}` dá uma variável para a execução. |
| Um [Webhook](/pt/docs/nodes/webhook/) | `body`, `headers`, `query_params`, `method` e `request_path` da requisição. |
| Um [Schedule](/pt/docs/nodes/schedule/) | Nada próprio. |
| Um [Error Trigger](/pt/docs/nodes/error-trigger/) | `error` e `execution`, sobre a execução que falhou. |

`flow_id` e `workspace_id` estão sempre lá, e nenhum passo consegue mudar.

## result

Quase todo nó deixa o que fez em `result`: a resposta de uma API, as linhas de uma consulta, o texto de um resumo. O próximo nó lê isso, e a maioria dos campos já tem ele como padrão, como o **Rows** de um insert, que é `{{result}}` até você mudar.

Cada passo substitui `result`. Para guardar um valor para os passos seguintes, dê um nome a ele:

- um nó [Variable](/pt/docs/nodes/variable/) guarda um valor com esse nome;
- um [passo de código](/pt/docs/nodes/evaluate-code/) pode colocar qualquer coisa no contexto: `Map.put(context, "customer", result)`.

O que cada nó deixa está na página dele, em **O que devolve**.

## Placeholders

Um campo lê o contexto com `{{caminho}}`:

| Você escreve | Você recebe |
| --- | --- |
| `{{result}}` | O resultado inteiro |
| `{{body.customer.email}}` | Uma chave dentro de outra |
| `{{result.rows.0.id}}` | O `id` da primeira linha: um número escolhe um item de uma lista |
| `Olá, {{body.name}}!` | Um texto com o valor escrito dentro |

Um caminho que não leva a nada vira texto vazio. Um objeto ou uma lista escritos dentro de um texto viram JSON. O inspetor escreve os caminhos para você: passe o mouse num valor e aperte **Copy as {{placeholder}}**.

### Em campos JSON

Campos que recebem JSON, como as linhas de um nó de banco, são lidos como JSON primeiro e preenchidos depois. Fora de aspas, um placeholder mantém o tipo; dentro de aspas, é escrito no texto:

```json
{"name": "{{body.name}}", "age": {{body.age}}, "tags": {{body.tags}}}
```

Assim, um valor que vem de fora não muda a forma que você escreveu. Um campo que é só um placeholder, como `{{result}}`, pega o valor como ele é.

### Em consultas

Um placeholder em SQL, CQL ou Cypher vai para o banco como parâmetro, nunca como parte da consulta. Veja [Bancos de dados](/pt/docs/guides/databases/).

### Campos que recebem um caminho

Alguns campos dizem onde ler, sem chaves: a **List** de um [For Each](/pt/docs/nodes/for-each/), o **Source** dos nós de CSV, as **Rows** do Google Sheets e a **Variable** de uma [Condition](/pt/docs/nodes/condition/). Escreva `body.items`, não `{{body.items}}`. A página do nó diz quando um campo é desses.

## Variáveis

As variáveis ficam em `variables` no contexto, e `{{nome}}` lê uma variável antes de uma chave do contexto com o mesmo nome. Elas vêm de um nó [Variable](/pt/docs/nodes/variable/), das `variables` de uma chamada da API ou da entrada de uma execução de teste.

## Os campos de um nó enquanto ele roda

Enquanto um nó roda, os campos dele ficam no contexto com os próprios nomes, e voltam ao que eram quando ele termina. Por isso os campos têm nomes como `response_body` e `switch_value`: um campo chamado `body` esconderia o corpo do webhook daquele nó.

## Até onde uma execução cresce

O contexto é salvo com a execução, então mantenha ele com dados. Uma lista de um [For Each](/pt/docs/nodes/for-each/), e as linhas de uma consulta, aceitam até 10.000 itens. Arquivos, como um download ou uma imagem, viajam em base64 dentro de `result`, e todo nó que recebe arquivo lê de volta. Valores longos são cortados no inspetor, não na execução.
