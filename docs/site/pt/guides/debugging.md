---
title: Depurando uma execução
description: Veja o que cada passo recebeu e mudou, rode de novo a partir de qualquer passo, e fixe dados para parar de chamar serviços reais enquanto monta.
sidebar:
  order: 5
---

Toda execução guarda o que aconteceu nela. O inspetor de execuções, embaixo do canvas, mostra passo a passo.

## Abrir uma execução

- Uma execução que você inicia pelo editor abre sozinha no inspetor.
- **Executions** lista as execuções de todos os fluxos, com o status. Abra uma para ver no editor do fluxo.
- O link de uma execução que falhou, como o `{{execution.url}}` que um [fluxo de erro](/pt/docs/guides/error-handling/#fluxos-de-erro) recebe, abre direto no inspetor.

O fluxo aparece como era quando a execução começou: uma execução guarda a sua [versão](/pt/docs/concepts/versions/).

## Ler um passo

Clique num passo da lista, ou em **Show on the canvas** para achar o nó. Para cada passo:

- **Input** é o contexto que ele recebeu. **Output** é o que ele mudou: o que adicionou, o que alterou e as chaves em **Removed**.
- **Tries** mostra cada tentativa de um passo que [tentou de novo](/pt/docs/guides/error-handling/#tentar-de-novo), com o erro.
- **Error** diz por que falhou.

**Filter keys and values** encontra um valor num contexto grande. **Copy JSON** copia um valor, e **Copy as {{placeholder}}** copia o caminho até ele, para colar num campo.

Valores longos são cortados para a execução ficar pequena, e uma execução com milhares de passos guarda os dados só dos últimos. Um passo com dados cortados não pode rodar de novo a partir dali.

## Rodar de novo

- **Run again** salva o fluxo e roda com a mesma entrada. Depois de corrigir um nó, é o jeito mais rápido de conferir.
- **Run from here** salva o fluxo e roda a partir daquele passo, com o contexto que ele recebeu. Os passos anteriores não rodam de novo, então uma execução que falhou no passo 8 de 10 não chama os passos 1 a 7 de novo.

Os dois rodam o rascunho.

## Dados fixados

Enquanto você monta, chamar uma API real a cada execução é lento, custa dinheiro ou manda mensagens de verdade. **Pin output** num passo faz as execuções do editor usarem aquela saída em vez de rodar o nó: o nó mostra um alfinete, e a execução sai pela mesma saída com os mesmos dados.

- Os dados podem ser editados na gaveta do nó, em **Pinned data**, como JSON. **Unpin** remove.
- Só as execuções do editor usam. A produção, a API e os agendamentos sempre rodam o nó.

## Rodar uma parte do fluxo

Coloque os nós em que você está trabalhando numa [seção](/pt/docs/start/editor/#notas-e-seções) e aperte o play dela. Só aquela seção roda.

## Testar com a requisição de um webhook

Um fluxo que começa num Webhook precisa de uma requisição para rodar. **Run Flow** num fluxo assim pede o corpo, os cabeçalhos e a query para mandar, então dá para testar sem chamar de fora.

## Quando nada aparece

- **A execução fica em Queued**: nenhum worker está pegando execuções. Veja `heddle status`, ou os logs do worker num servidor.
- **Um webhook responde 404**: o fluxo não está publicado, o caminho ou o método são outros, ou a chamada está indo para outro servidor.
- **Um agendamento não dispara**: o fluxo não está publicado, ou o cron está em outro fuso: ele é em UTC.
