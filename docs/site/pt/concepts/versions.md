---
title: Rascunhos e versões
description: Edite um rascunho enquanto a produção roda o que você publicou, guarde cada versão com quem mudou e quando, e volte com um clique.
sidebar:
  order: 3
---

Um fluxo tem dois lados. O **rascunho** é o que o canvas mostra, e muda conforme qualquer pessoa edita. A **versão publicada** é o que a produção roda. Eles ficam separados até você publicar, então dá para mexer num fluxo que está no ar sem quebrar.

## O que roda o quê

| Iniciado por | Roda |
| --- | --- |
| **Run Flow**, o play de uma seção, **Run from here** | O rascunho, como está |
| Webhooks, agendamentos, fluxos de erro | A versão publicada |
| A API | A versão publicada, a não ser que a chamada peça `version=draft` |
| O chat de IA, e `run_flow` e `test_flow` pelo MCP | O rascunho |

Um fluxo que nunca foi publicado não roda sozinho: os webhooks dele respondem `404` e os agendamentos não disparam. Cada execução guarda a versão que rodou, então uma execução da semana passada mostra o fluxo como ele era.

## Publicando

Aperte **Publish**, escreva o que mudou e confirme. A publicação confere o fluxo inteiro: uma expressão cron pela metade passa no rascunho, mas não na produção, e o diálogo diz o que corrigir.

O selo ao lado do nome diz como estão as coisas:

- **Not published**: a produção ainda não roda nada.
- **Live · v4**: a produção roda o que está no canvas.
- **Unpublished changes**: o rascunho andou, e a produção continua rodando a última versão publicada.

Admins e editores podem publicar. O chat de IA também, mas pergunta antes.

## O histórico

Abra **⋯ → Versions**. Cada versão mostra o número, quando foi feita, quem fez, quem mais mexeu no rascunho desde a anterior e a nota. São três tipos:

- **Publicada**, feita pelo **Publish**, com nota.
- **Checkpoint**, feita sozinha enquanto o fluxo é editado, mais ou menos a cada dez minutos, e quando todo mundo sai dele.
- **Execução**, o rascunho como estava quando alguém rodou pelo editor.

Clique numa versão para ver no canvas o que ela mudou em relação à anterior: nós adicionados e alterados ficam marcados, e os removidos aparecem tracejados onde estavam.

Checkpoints e versões de execução com mais de 30 dias são apagados, a não ser que uma execução tenha usado ou que sejam a mais nova. As versões publicadas ficam.

## Voltando atrás

A partir de uma versão no histórico:

- **Restore** coloca ela no rascunho. O rascunho que você tinha vira um checkpoint antes, então dá para desfazer. A produção continua rodando o que rodava até você publicar.
- **Publish this version** coloca ela de volta na produção, sem mexer no rascunho. É o jeito rápido de sair de uma publicação ruim.

## Pela API

A API faz o mesmo: listar versões, ler uma, publicar o rascunho, publicar uma versão antiga e restaurar. Veja a [referência da API](/pt/docs/reference/api/#versões).
