---
title: Edição em grupo
description: Várias pessoas, e a IA, no mesmo fluxo ao mesmo tempo, com cursores ao vivo, salvamento automático e um desfazer só seu.
sidebar:
  order: 4
---

Um fluxo pode estar aberto em vários navegadores, e todo mundo trabalha no mesmo canvas. Não tem nada para juntar nem botão de salvar.

## O que você vê dos outros

- **Avatares** no alto: quem mais está com o fluxo aberto. O seu não aparece.
- **Cursores** com o nome, onde cada um aponta no canvas.
- **Anéis** na cor de cada pessoa em volta dos nós que ela selecionou, e uma marca no nó cuja gaveta ela tem aberta.
- **Arrastos** enquanto acontecem: um nó que alguém move desliza na sua tela também.

Clique num avatar para **seguir** a pessoa: sua visão vai aonde o cursor dela vai, até você mexer no canvas ou clicar de novo.

## Como as mudanças se encontram

Toda mudança vai para um processo no servidor, um por fluxo, que coloca as mudanças em ordem e manda para todo mundo. Duas pessoas podem mudar nós diferentes, ou campos diferentes do mesmo nó, ao mesmo tempo, e as duas mudanças ficam. Quando duas pessoas mudam o mesmo campo, vale a última.

Na gaveta do nó, um campo que outra pessoa muda atualiza na sua frente, menos aquele em que você está digitando. O editor de código avisa quando alguém mudou o código depois que você abriu, e deixa você carregar o dela ou manter o seu.

## Salvando

As mudanças são salvas logo depois de feitas, e **Saving...** aparece ao lado do nome do fluxo até terminar. Se a conexão cai, aparece **Reconnecting...**, e o que você fez nesse meio tempo é mandado quando ela volta. Uma execução, ou uma publicação, sempre salva antes.

## Desfazer

**Ctrl+Z** volta a sua última mudança, nunca a de outra pessoa. Se alguém mudou a mesma coisa depois de você, desfazer coloca de volta o que você tinha, por cima do dela.

## No terminal

O [Treadle](https://github.com/heddlehq/Treadle), o editor de terminal, edita o mesmo fluxo ao vivo. Quem está com ele aberto lá aparece como qualquer pessoa: um avatar, anéis nos nós que selecionou e um cursor no nó em que está. Essa pessoa também te vê, com o seu cursor. Qualquer outro cliente que edite pela API pode fazer o mesmo: veja [Editar junto](/pt/docs/reference/api/) na API.

## A IA no canvas

Quando o chat de IA edita um fluxo, ele aparece entre os avatares enquanto trabalha, e os nós que ele muda piscam. As mudanças dele passam pelo mesmo processo que as de todo mundo, então nunca atropelam o que você está fazendo. O mesmo vale para a API, o MCP e as importações: o que eles mudam aparece em todo canvas aberto.

## Quem pode editar

Viewers e operators veem o canvas e quem está nele, mas não mudam nada. Editores e admins podem. Veja [Workspaces e papéis](/pt/docs/concepts/workspaces/).
