---
title: API REST
description: Crie, altere, rode, publique e inspecione fluxos por HTTP, com uma chave de API.
sidebar:
  order: 1
---

Tudo que o editor faz num fluxo, a API faz também. A especificação completa está em [openapi.yaml](/docs/openapi.yaml), que ferramentas como Postman, Insomnia e geradores de código leem.

## Autenticação

Crie uma chave em **API keys** e mande em toda requisição:

```bash
curl -H "Authorization: Bearer hd_live_ab12cd34_..." https://seu-heddle/api/v1/workflows
```

`X-Heddle-API-Key: <chave>` também funciona, para ferramentas que não conseguem mandar `Authorization`.

Uma chave pertence a uma pessoa e a um workspace. Ela só alcança os fluxos daquele workspace, e não faz mais que o papel do dono lá, no momento de cada requisição:

| Papel | Pode |
| --- | --- |
| `viewer` | Ler fluxos, execuções e nós |
| `operator` | Também rodar fluxos |
| `editor` | Também criar, mudar, apagar e publicar fluxos, e usar o agente |
| `admin` | Também gerenciar o workspace, os membros e todas as chaves dele |

As chaves também têm **escopos**, escolhidos na criação: `workflows:read`, `workflows:write`, `workflows:delete`, `executions:read`, `executions:write` e `nodes:read`. Uma requisição precisa do escopo e do papel.

## Respostas

| Status | Quer dizer |
| --- | --- |
| `200`, `201`, `202` | Feito, criado, na fila |
| `401` | Sem chave, chave errada, ou o dono saiu do workspace |
| `403` | O escopo ou o papel não permite |
| `404` | Não existe, ou está em outro workspace |
| `409` | O fluxo nunca foi publicado, e a chamada precisa de uma versão publicada; ou, no `/changes`, operações sobre algo que não existe mais |
| `422` | O que foi mandado não é válido: `errors` diz o quê |
| `429` | Mais de 100 requisições num minuto com esta chave (1200 na edição ao vivo) |

## Endpoints

### Fluxos

| Método e caminho | Faz |
| --- | --- |
| `GET /api/v1/workflows` | Lista os fluxos |
| `POST /api/v1/workflows` | Cria um fluxo |
| `GET /api/v1/workflows/{id}` | Lê um fluxo, com os nós e as conexões |
| `PATCH /api/v1/workflows/{id}` | Muda alguns campos, como o nome ou os nós |
| `PUT /api/v1/workflows/{id}` | Substitui os campos mandados |
| `DELETE /api/v1/workflows/{id}` | Apaga um fluxo |

Mudar nós ou conexões muda o rascunho, e aparece na hora em todo canvas aberto.

```bash
curl -X POST https://seu-heddle/api/v1/workflows \
  -H "Authorization: Bearer $HEDDLE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "workflow": {
      "name": "Boas-vindas a clientes",
      "nodes": [
        {"id": "start", "type": "Start", "label": "Start", "controls": {}},
        {"id": "done", "type": "Output", "label": "Done", "controls": {}}
      ],
      "connections": [
        {"source": "start", "sourceOutput": "exec", "target": "done", "targetInput": "exec"}
      ]
    }
  }'
```

Um nó precisa de um `id`, de um `type` da [lista de nós](/pt/docs/nodes/) e de `controls`, os valores dos campos pelo nome. Pode ter `label`, `settings` e `position`; um sem posição é colocado no canvas sozinho.

### Execuções

| Método e caminho | Faz |
| --- | --- |
| `POST /api/v1/workflows/{id}/executions` | Coloca uma execução na fila |
| `GET /api/v1/workflows/{id}/executions` | Lista as execuções, com `page`, `per_page` e filtros |
| `GET /api/v1/workflows/{id}/executions/{id da execução}` | Lê uma execução: status, entrada, contexto final, passos |

```bash
curl -X POST https://seu-heddle/api/v1/workflows/12/executions \
  -H "Authorization: Bearer $HEDDLE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"input": {"variables": {"customer_id": 42}}}'
```

Uma execução usa a versão publicada. `"version": "draft"` no corpo roda o rascunho como está salvo.

### Versões

| Método e caminho | Faz |
| --- | --- |
| `GET /api/v1/workflows/{id}/versions` | Lista as versões, da mais nova à mais antiga |
| `GET /api/v1/workflows/{id}/versions/{id da versão}` | Lê uma, com o grafo |
| `POST /api/v1/workflows/{id}/publish` | Publica o rascunho, com uma `note` opcional |
| `POST /api/v1/workflows/{id}/versions/{id da versão}/publish` | Coloca uma versão antiga de volta na produção |
| `POST /api/v1/workflows/{id}/versions/{id da versão}/restore` | Coloca uma versão no rascunho |

Veja [Rascunhos e versões](/pt/docs/concepts/versions/).

### Editar junto

| Método e caminho | Faz |
| --- | --- |
| `GET /api/v1/workflows/{id}/live` | Acompanha o rascunho enquanto as pessoas editam, em server-sent events |
| `POST /api/v1/workflows/{id}/changes` | Muda o rascunho sem desfazer o que os outros mudaram |
| `POST /api/v1/workflows/{id}/focus` | Diz para quais nós você está apontando |

`PUT` e `PATCH` deixam o rascunho igual ao que você manda, o que desfaz o que outra pessoa mudou desde que você leu. Para editar enquanto outros editam, como o [Treadle](https://github.com/heddlehq/Treadle) faz:

1. Abra o `live`. Enquanto ele está aberto, você está no fluxo como quem tem o canvas aberto: os outros te veem, e o stream diz quem mais está lá. Ele manda primeiro um `ready`, com o seu `client`, se você pode editar (`can_edit`) e o `graph`; depois um `change` com o grafo depois de cada mudança, `presence` quando alguém entra, sai ou seleciona algo, e `cursor` com a posição do ponteiro de cada um. Outro `ready` quer dizer que o stream se perdeu: pegue o grafo dele como está.
2. Mande cada mudança para `changes` com `base`, o grafo que você tinha por último, e `graph`, o que você tem agora. Só o que mudou entre os dois é aplicado, por cima do que os outros fizeram; a resposta traz o rascunho logo depois. Quem muda o mesmo campo por último ganha.
3. Mande `focus` com o seu `client` e os nós em `selected`, e os outros os veem na sua cor. Um cliente sem ponteiro, como um terminal, manda também um `cursor`, com `x` e `y` no fluxo, e os canvas o desenham como seu.

A edição ao vivo conta à parte do resto da API, até 1200 requisições por minuto por chave. Veja [Editar junto](/pt/docs/concepts/collaboration/).

### O agente

| Método e caminho | Faz |
| --- | --- |
| `GET /api/v1/workflows/{id}/agent` | Lê a conversa com o agente do fluxo |
| `POST /api/v1/workflows/{id}/agent/messages` | Manda uma mensagem |
| `GET /api/v1/workflows/{id}/agent/events` | Acompanha o trabalho dele, por server-sent events |
| `POST /api/v1/workflows/{id}/agent/decision` | Responde quando ele pede para rodar ou publicar |
| `POST /api/v1/workflows/{id}/agent/new` | Começa uma conversa nova |
| `POST /api/v1/workflows/{id}/agent/stop` | Para o que ele está fazendo |

É assim que o [Treadle](https://github.com/heddlehq/Treadle) conversa com o agente. Veja [O AI Agent e o chat](/pt/docs/guides/ai-agent/).

### Nós

| Método e caminho | Faz |
| --- | --- |
| `GET /api/v1/nodes` | Lista todos os nós, com campos e saídas |
| `GET /api/v1/nodes/{type}` | Lê um |
| `GET /api/v1/health` | Se o servidor está no ar, sem chave |
