---
title: O editor
description: Um passeio pelo canvas, a gaveta do nó, o inspetor de execuções, as seções, o chat de IA e a barra de cima.
sidebar:
  order: 4
---

O editor é onde um fluxo é desenhado e testado. Ele salva enquanto você trabalha, e todo mundo com o fluxo aberto vê o mesmo canvas.

## A barra de cima

Da esquerda para a direita:

- **Flows / nome**: volta para a lista, e o nome do fluxo. Passe o mouse no nome e aperte o lápis para renomear.
- **Status**: **Live · v3** quando a produção roda o que está no canvas, **Unpublished changes** quando o rascunho andou, **Not published** quando nunca foi publicado. Clique nele para abrir as versões. Enquanto salva, aparece **Saving...** ao lado.
- **Pessoas**: quem mais está com o fluxo aberto. Clique em alguém para seguir o cursor dela. Veja [Edição em grupo](/pt/docs/concepts/collaboration/).
- **⋯**: **Versions**, as **Settings** do fluxo (como o [fluxo de erro](/pt/docs/guides/error-handling/#fluxos-de-erro)) e **Import from a file**.
- **Publish** coloca o rascunho em produção, e **Run Flow** roda o rascunho agora.

## O canvas

- **Adicionar um nó**: arraste da barra lateral, ou clique com o botão direito no canvas e escolha **Create Node**. A busca da barra encontra pelo nome e pelo que o nó acessa, como `postgres`, e guarda os que você usou por último.
- **Conectar**: arraste de uma saída, à direita do nó, até uma entrada, à esquerda. Várias conexões podem sair de uma saída: elas rodam na ordem em que foram feitas.
- **Selecionar**: clique num nó, **Ctrl**+clique para somar outros, ou segure **Shift** e arraste uma caixa em volta de vários. Depois, **Ctrl+C** e **Ctrl+V** copiam, até para outro fluxo, e **Delete** remove.
- **Desfazer**: **Ctrl+Z** e **Ctrl+Y**, ou o menu do botão direito. O desfazer volta só o que você fez, nunca o que outra pessoa fez.
- **Navegar**: arraste o canvas vazio, e use a rolagem para dar zoom.

## A gaveta do nó

Passe o mouse num nó e aperte a engrenagem. A gaveta mostra o nome do nó e os campos, e cada mudança vale enquanto você digita. Embaixo dos campos, **When it fails** diz o que o nó faz quando falha: tenta de novo, segue em frente ou pega um caminho de erro. Veja [Tratando erros](/pt/docs/guides/error-handling/).

Os campos que aceitam `{{placeholders}}` leem os dados da execução. Veja [Dados numa execução](/pt/docs/concepts/context/).

## Notas e seções

Os botões no canto superior esquerdo do canvas adicionam cartões de **Title**, **Text** e **Note**, para explicar o fluxo a quem for ler, e **Section**, uma moldura em volta de nós.

Uma seção pode rodar sozinha, pelo botão de play dela, o que ajuda a testar uma parte de um fluxo grande. Desligue **Run with the flow** nas configurações dela e ela só roda por esse botão: um lugar para passos de manutenção, como preencher uma tabela uma vez.

## O inspetor de execuções

Depois de uma execução, o inspetor embaixo do canvas lista os passos. Clique num para ver o que ele recebeu (**Input**), o que mudou (**Output**), quantas tentativas levou e o erro. Dali:

- **Copy as {{placeholder}}** copia o caminho até um valor.
- **Pin output** faz as execuções do editor usarem essa saída em vez de rodar o nó.
- **Run from here** roda o fluxo de novo a partir daquele passo, com os dados que ele tinha.
- **Run again** roda o fluxo inteiro de novo com a mesma entrada.

Veja [Depurando uma execução](/pt/docs/guides/debugging/).

## O chat de IA

Com uma IA configurada, o chat no canto inferior direito monta e altera fluxos para você. Diga o que precisa: ele lê o fluxo, planeja a mudança e edita o canvas na sua frente. Ele sempre pergunta antes de rodar ou publicar. Veja [O AI Agent e o chat](/pt/docs/guides/ai-agent/#o-chat-no-editor).

## O terminal

Em instalações locais, um admin pode ligar o **Terminal** na página **AI**. Ele abre o Claude Code no editor, já conectado a este Heddle por MCP. Veja [MCP](/pt/docs/reference/mcp/).

## Idioma e tema

O menu com o seu nome, no pé da barra lateral, abre **Preferências**: o idioma da interface, ou o do seu navegador, e o tema claro, escuro ou o do sistema. Eles ficam salvos na sua conta, então acompanham você em qualquer navegador.
