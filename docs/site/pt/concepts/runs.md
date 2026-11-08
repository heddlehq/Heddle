---
title: Como uma execução anda
description: Onde uma execução começa, como segue as saídas, ramifica, repete, junta e espera, e o que acontece quando um passo falha.
sidebar:
  order: 2
---

Uma execução vai de nó em nó pelas conexões. Cada nó faz o seu trabalho, escolhe uma das suas saídas, e a execução segue o que está ligado nela.

## Onde começa

- **Run Flow** e as execuções pela API começam no nó **Start**. Um fluxo sem Start começa no primeiro gatilho.
- Uma chamada a um [Webhook](/pt/docs/nodes/webhook/) começa naquele Webhook.
- Um [Schedule](/pt/docs/nodes/schedule/) começa nele mesmo, quando chega a hora.
- Uma execução iniciada pela falha de outro fluxo começa no [Error Trigger](/pt/docs/nodes/error-trigger/).
- Uma [seção](/pt/docs/start/editor/#notas-e-seções) rodada pelo play começa nos nós a que nada da seção leva.

As execuções do editor rodam o **rascunho**. Webhooks, agendamentos, fluxos de erro e a API rodam a **versão publicada**. Veja [Versões](/pt/docs/concepts/versions/).

## Saídas

A maioria dos nós tem uma saída, `exec`. Os nós que acessam um serviço têm duas, `success` e `error`, para o fluxo tratar o serviço fora do ar. Os nós de controle de fluxo escolhem entre várias:

| Nó | Saídas |
| --- | --- |
| [Condition](/pt/docs/nodes/condition/) | `true`, `false` |
| [Switch](/pt/docs/nodes/switch/) | `case 1` a `case 4`, `otherwise` |
| [For Each](/pt/docs/nodes/for-each/) | `item` para cada item, depois `done` |
| [Wait](/pt/docs/nodes/wait/) | `exec`, ou `timeout` quando a chamada não veio |
| [AI Agent](/pt/docs/nodes/ai-agent/) | `success`, `error` e `tools`, que não é seguida, mas oferecida ao agente |

## Ramos

Várias conexões podem sair de uma saída. A execução segue uma depois da outra, na ordem em que foram feitas, e cada ramo recebe o contexto como o nó deixou. Uma execução termina quando nenhum ramo tem mais nada para rodar.

## Repetição

Um [For Each](/pt/docs/nodes/for-each/) roda os nós da saída `item` uma vez por item, em ordem, e depois segue por `done` com o que cada passada deixou.

## Juntando ramos

Um [Merge](/pt/docs/nodes/merge/) espera todas as conexões que chegam nele e segue uma vez, com os resultados de todas. Um ramo que uma Condition nunca tomou não segura ele para sempre: quando não sobra mais nada para rodar, o Merge segue com o que chegou.

## Esperando

Um [Wait](/pt/docs/nodes/wait/) pausa a execução por um tempo, até uma data, ou até alguém chamar o endereço dele. A execução é salva, não ocupa nenhum worker enquanto espera e sobrevive a reinícios.

## Quando um passo falha

Um passo falha quando o serviço responde com erro, o código lança uma exceção ou um campo está errado. Aí, nesta ordem:

1. **Tenta de novo**, se as configurações dele dão tentativas, esperando entre elas.
2. **Pega o caminho de erro**: a saída `error`, quando tem algo ligado nela.
3. **Segue em frente**, se as configurações mandam, pela saída de sempre, com o erro em `result`.
4. **Senão, a execução falha**, e o [fluxo de erro](/pt/docs/guides/error-handling/#fluxos-de-erro) do fluxo, se houver, roda.

Veja [Tratando erros](/pt/docs/guides/error-handling/).

## O que fica guardado

Cada execução fica guardada com o status, a entrada, o contexto com que terminou e cada passo: o que recebeu, o que mudou, quanto tempo levou e quantas tentativas precisou. Abra pela página **Executions**, ou no inspetor do editor. Uma execução iniciada no editor também pode usar [dados fixados](/pt/docs/guides/debugging/#dados-fixados) em vez de rodar um nó.

## Onde as execuções rodam

As execuções passam por uma fila no Postgres e rodam nos **workers**, que podem estar em outras máquinas que não a do editor. Uma execução que estava rodando quando o worker morreu começa de novo do início depois de um tempo, então deixe seguros para repetir os passos que cobram dinheiro ou mandam mensagens. Veja [Escala](/pt/docs/self-hosting/scaling/).
