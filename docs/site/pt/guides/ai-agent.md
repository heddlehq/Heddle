---
title: O AI Agent e o chat
description: Dê seus passos como ferramentas a um agente, guarde a memória dele entre execuções e deixe o chat do editor montar fluxos para você.
sidebar:
  order: 7
---

O Heddle tem IA em dois lugares. O nó **AI Agent** trabalha dentro de uma execução, com seus passos como ferramentas. O **chat** do editor trabalha no próprio fluxo, montando e alterando com você. Os dois precisam de um [provedor de IA](/pt/docs/guides/ai-providers/).

## O nó AI Agent

O agente recebe um **Prompt**, pensa, chama ferramentas, lê o que elas respondem e continua até ter uma resposta ou chegar em **Max steps**. A resposta sai por `success` em `result`.

```text
Prompt: Um cliente escreveu: "{{body.message}}". O email dele é {{body.email}}.
        Encontre o último pedido dele e responda quando chega.
```

### Ferramentas

Todo nó ligado na saída `tools` do agente vira uma ferramenta, com o nome tirado do rótulo do nó, como `buscar_pedido` para **Buscar pedido**. Dê às ferramentas nomes do que elas fazem, e o agente escolhe a certa com mais frequência.

Numa ferramenta, **os campos que você deixa em branco são o que o agente preenche**, e os que você preenche ficam como estão, fora do alcance dele. Um **SQL: Select Rows** com **Table** em `orders` e **Where** em branco deixa o agente buscar pedidos, e só pedidos. Ele nunca escolhe uma credencial ou um modelo, e nunca escreve código.

Uma ferramenta pode ser um ramo inteiro: o agente chama o primeiro nó, e os passos depois dele rodam também, com o que o agente passou em `input`. O que o ramo deixa em `result` é o que o agente lê de volta.

Depois da execução, `tool_calls` lista cada ferramenta que ele chamou, com os argumentos e se funcionou, e o inspetor mostra os passos de cada ferramenta.

### Respostas como dados

**Reply as** `JSON` pede um único valor JSON, que vira `result` já decodificado, então o próximo nó lê `{{result.priority}}`. Diga no prompt as chaves que você quer:

```text
Responda com {"priority": "low" | "high", "summary": "..."}
```

Uma resposta que não é JSON sai por `error`.

### Memória

**Memory key** guarda a conversa entre execuções. Execuções com a mesma chave continuam de onde a última parou: `{{body.customer_id}}` dá a cada cliente a sua própria conversa. Em branco, ele esquece tudo depois de cada execução.

### Mantendo seguro

- Um agente só faz o que as ferramentas dele fazem. Preencha o que ele não deve mudar: a tabela, o canal, o destinatário.
- Dê a uma ferramenta de banco um usuário só com as permissões necessárias, porque o agente escreve os campos em branco, inclusive a consulta.
- **Max steps** limita quantas vezes ele chama o modelo numa execução, 10 por padrão.
- Um [Wait](/pt/docs/nodes/wait/) não pode ser ferramenta.

## O chat no editor

O chat no canto inferior direito do editor trabalha no fluxo aberto. Peça o que precisa, do seu jeito:

> Quando chegar um lead num webhook, salve na tabela de leads e avise o #vendas no Slack, com o nome e a empresa do lead.

Ele lê o fluxo e os nós disponíveis, planeja a mudança e edita o canvas na sua frente: ele aparece entre os avatares, e os nós que ele muda piscam. Depois ele pode testar o fluxo e corrigir o que falhou.

- Ele **sempre pergunta** antes de rodar ou publicar um fluxo, e antes de restaurar uma versão. **Always** deixa ele rodar sem perguntar pelo resto da conversa; publicar pergunta toda vez.
- As mudanças dele são como as de qualquer pessoa: **Ctrl+Z** não desfaz para você, mas o [histórico de versões](/pt/docs/concepts/versions/) traz de volta qualquer estado anterior.
- Uma conversa é sua e do fluxo. Abrir o fluxo de novo começa uma nova, a não ser que ele ainda esteja trabalhando.

**Flows → Create with AI** começa um fluxo novo a partir de uma descrição do mesmo jeito.

## De outras ferramentas

O mesmo agente responde pela API, que é como o [Treadle](https://github.com/heddlehq/Treadle) conversa com ele no terminal, e o Claude Code ou qualquer cliente MCP pode montar fluxos com as mesmas ferramentas. Veja [MCP](/pt/docs/reference/mcp/).
