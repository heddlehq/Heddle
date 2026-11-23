---
title: Integrações
description: Instale os serviços que os fluxos de um workspace acessam, ou escreva sua própria integração como um manifesto.
sidebar:
  order: 2
---

A página **Integrations** lista os serviços que um workspace pode acessar. A barra de nós do editor mostra só os instalados no workspace.

- As integrações **oficiais** são mantidas pelo Heddle e vêm com ele.
- As integrações da **comunidade** vêm do [catálogo](https://github.com/heddlehq/integrations). O Heddle não as revisa, e os nós delas mandam o que recebem para o serviço delas, então só admins do workspace instalam.
- Remover uma integração tira os nós dela da barra. Se um fluxo ainda usa a integração, ela continua instalada.

## Criar uma integração

Um admin do workspace pode escrever uma em **Create integration**. Uma integração é um manifesto em YAML: o endereço do serviço, a credencial e as ações como requisições HTTP. Cada ação vira um nó, com uma saída `success` e uma `error`.

```yaml
id: acme_crm
name: Acme CRM
version: 1.0.0
base_url: https://api.acme.example/v1/
credential:
  fields:
    - name: api_key
      label: API key
      secret: true
  auth:
    type: bearer
    token: "{{credential.api_key}}"
actions:
  - name: Get Contact
    fields:
      - name: id
        label: Contact ID
    request:
      method: GET
      path: "contacts/{{fields.id}}"
```

A página confere o manifesto enquanto você escreve e mostra o que corrigir. **Create and install** instala no workspace, como uma integração da comunidade da instância, então outros workspaces também podem instalar.

- O `id` não pode ser de outra integração, e os nós não podem ter o nome de nós oficiais.
- O que um manifesto pode ter (paginação, gatilhos, OAuth2) está no [guia do Bobbin](https://hexdocs.pm/bobbin/manifest.html), e integrações em Elixir [em outro](https://hexdocs.pm/bobbin/packages.html). Para compartilhar, abra um pull request em [heddlehq/integrations](https://github.com/heddlehq/integrations).
