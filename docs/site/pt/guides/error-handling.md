---
title: Tratando erros
description: Tente um passo de novo, pegue um caminho de erro, siga em frente mesmo assim, ou dispare outro fluxo quando uma execução falha.
sidebar:
  order: 4
---

Serviços caem, tokens expiram e os dados chegam em formatos que ninguém esperava. O Heddle dá a cada passo quatro jeitos de lidar com uma falha, e a cada fluxo mais um.

## Tentar de novo

Na gaveta do nó, em **When it fails**:

- **Tries again**: quantas vezes mais o passo roda antes de falhar, até 10.
- **Seconds between tries**: a espera antes da primeira tentativa nova, até 300.
- **Wait twice as long after each try**: dobra a espera a cada vez, em vez de manter.

Três tentativas com 2 segundos, dobrando, tentam de novo depois de 2, 4 e 8 segundos. O inspetor mostra cada tentativa e o erro dela.

Repita os passos que podem ser repetidos com segurança: um GET, um upsert, uma mensagem que tudo bem mandar duas vezes.

## Pegar um caminho de erro

Os nós que acessam um serviço têm uma saída `error`. Com **Then** em **Stop the run**, o padrão, ligue algo nela e a falha vai para lá em vez de derrubar a execução, com o erro em `result`:

```json
{"error": "Slack refused it: channel_not_found"}
```

Dali você avisa alguém, registra a falha numa tabela ou responde o webhook com `502`.

## Seguir em frente mesmo assim

Em **Then**, escolha **Continue** e a execução segue pela saída de sempre do nó, com `{"error": "..."}` em `result`. Use para passos que são bons de ter, como um log ou uma notificação, para a falha deles não parar o que importa.

## Dar uma saída de erro a qualquer nó

Em **Then**, escolha **Use an error output** e o nó ganha uma saída `error`, mesmo que não tivesse, como o **Evaluate Code**.

## Fluxos de erro

Quando uma execução falha e nada acima tratou, roda o **fluxo de erro** do fluxo. Um fluxo de erro pode vigiar muitos fluxos: monte uma vez e escolha ele em **⋯ → Settings** de cada fluxo.

Um fluxo de erro começa com um [Error Trigger](/pt/docs/nodes/error-trigger/) e recebe o erro e a execução que falhou:

```text
{{error.message}}       Slack refused it: channel_not_found
{{error.node_label}}    Avisar o time
{{execution.flow_name}} Novos leads
{{execution.url}}       um link que abre a execução no inspetor
```

Um comum manda isso para o Slack ou por email. O fluxo de erro roda a versão publicada dele, então publique, e uma falha dentro dele não dispara outro.

## Falhar de propósito

Para parar uma execução quando os dados estão errados, coloque uma [Condition](/pt/docs/nodes/condition/) na frente e, no lado ruim, um **Evaluate Code** que lança um erro:

```elixir
raise "O pedido não tem cliente"
```

A execução falha com essa mensagem, e o fluxo de erro recebe ela.
