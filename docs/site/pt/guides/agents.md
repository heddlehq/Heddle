---
title: Agentes
description: Agentes que moram no seu workspace, lembram de cada cliente, fazem follow-up sozinhos e trabalham juntos.
sidebar:
  order: 8
---

O nó [AI Agent](/pt/docs/guides/ai-agent/) faz uma tarefa dentro de uma run e esquece quando ela acaba. Um **agente** continua vivo: ele tem nome, guarda o que aprende sobre cada cliente entre as mensagens, volta a escrever três dias depois e pergunta a outros agentes quando precisa. Os seus fluxos são as mãos dele.

Agentes precisam de um [provedor de IA](/pt/docs/guides/ai-providers/). Eles são feitos com o [Jido](https://hex.pm/packages/jido), e você não precisa conhecer o Jido.

## Comece por um modelo

Na página **Fluxos**, **A partir de um modelo** tem quatro agentes prontos para testar:

- **Atendente** atende clientes no chat, lembra de cada um e abre um chamado quando não resolve.
- **SDR com follow-up** conversa com cada lead, guarda o estágio dele e faz follow-up três dias depois se ele sumir.
- **Cobrança** lembra cada cliente de uma fatura atrasada, registra o que ele promete e pede aprovação antes de oferecer desconto.
- **Time de triagem** são três agentes num fluxo só: um agente de triagem que pergunta aos agentes Billing e Tech quando precisa.

Publique o fluxo, abra o nó **Agent** e clique em **Conversar** para falar com ele.

## Um agente é um fluxo

Um agente é um fluxo que começa no gatilho **Agent**. Publicar o fluxo cria o agente, e cada mensagem para ele é uma run.

```text
Agent → Agent: Think → Agent: Reply
            └ tools → Buscar pedido
```

No gatilho:

- **Name**: como outros fluxos o encontram, e como ele aparece no chat.
- **Instructions**: quem ele é e como trabalha, em palavras simples.
- **State**: o que ele guarda, em JSON com o valor inicial de cada campo: `{"stage": "new", "attempts": 0}`. O valor inicial define o tipo.

O **Agent: Think** responde com o modelo, usando os nós ligados na saída `tools`, como o AI Agent faz. O **Agent: Reply** manda a resposta de volta. No caminho, a run lê `{{agent.message}}`, `{{agent.state}}` e `{{agent.from}}`.

## Instâncias

Cada mensagem diz uma **chave**, como o id ou o email do cliente, e cada chave é uma **instância** do agente, com estado e conversa próprios. Sem chave, é `main`, para um agente que é único.

As mensagens de uma instância são tratadas uma de cada vez, na ordem em que chegaram, então duas nunca a mudam ao mesmo tempo. O que uma run muda só fica guardado se ela termina bem.

A gaveta do gatilho mostra cada instância, com o estado, as mensagens, o que gastou hoje e o que tem agendado.

## O que ele lembra

- **A conversa**: as últimas 20 mensagens vão junto com cada nova. As mais antigas viram um resumo curto, então uma conversa de meses ainda cabe.
- **O estado**: o **Agent: Set State** muda o estado, como `{"stage": "won"}`. O Think também tem a tool **remember**, então o agente guarda sozinho o que aprende, como o nome do cliente.

## Falando com ele

- **Pessoas**: a gaveta do gatilho tem um **link de chat**. Qualquer pessoa com ele conversa com o agente, cada uma numa conversa própria, que é uma instância. Coloque no seu site ou mande por email.
- **Outros canais**: um fluxo que recebe mensagens do WhatsApp ou do Slack as manda com o **Agent: Ask** e responde com o que o agente disse.
- **Fluxos**: o **Agent: Send Message** manda e segue. O **Agent: Ask** espera a resposta, sem ocupar worker.
- **O relógio**: o **Agent: Schedule** manda uma mensagem para o agente mais tarde, como um follow-up em três dias. **Call off the ones set before** move o follow-up cada vez que o cliente escreve. O **Agent: Cancel Schedule** cancela.
- **Eventos**: o **Agent: Publish Event** avisa o workspace que algo aconteceu, como `deal.won`, e todo fluxo que começa no **When an Agent Publishes** começa.
- **MCP**: `list_agents`, `read_agent` e `message_agent` deixam um assistente como o Claude conversar com os seus agentes.

## Agentes trabalhando juntos

Liste os agentes que um pode perguntar no campo **Agents it can ask** do Think. Ele ganha a tool **ask_agent**: a run espera a resposta do outro agente, sem ocupar worker, e o agente continua com ela. Um agente não pode ser perguntado de volta por quem está esperando por ele, porque nenhum dos dois responderia.

## Com segurança

- **Aprovação**: liste tools em **Tools that need approval** do Think, como `offer_discount`. Quando o agente quer usar uma, a run espera na página **Aprovações**, e a tool só roda depois que uma pessoa aprova.
- **Limites**: no gatilho, **Messages per hour** e **Spending per day** (US$) por instância. Uma mensagem além deles falha a run, dizendo por quê.
- **Quem pode mandar mensagem**: nomes de agentes, `chat` para pessoas, `flows` para qualquer fluxo, ou `flow:ID`. Em branco, qualquer um.
- **Sem loop infinito**: agentes mandando mensagem uns aos outros param em 5 mensagens.
- **Pausa**: o **Agent: Pause or Resume** faz um agente, ou uma instância, parar de receber mensagens.

## Mudando um agente

Publique uma versão nova, e cada instância passa para ela na próxima mensagem: os campos guardados continuam quando o tipo é o mesmo, os novos começam com o valor inicial, e os removidos saem.

O **Agent: Read Agent** e o **Agent: List Instances** leem instâncias de qualquer fluxo, e o **Agent: Reset Instance** e o **Agent: End Instance** esquecem uma.
