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
| `409` | O fluxo nunca foi publicado, e a chamada precisa de uma versão publicada |
| `422` | O que foi mandado não é válido: `errors` diz o quê |
| `429` | Mais de 100 requisições num minuto com esta chave |

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
