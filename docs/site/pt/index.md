---
title: Documentação do Heddle
description: Monte, rode e publique automações num canvas visual, com IA, código e os serviços que você usa.
sidebar:
  label: Visão geral
  order: 0
---

O Heddle é um orquestrador de fluxos que você mesmo hospeda. Você desenha um fluxo num canvas, nó por nó, e o Heddle roda: quando você aperta **Run**, num horário, quando um webhook é chamado ou pela API. Ele roda na BEAM, então milhares de execuções acontecem ao mesmo tempo, uma que falha não derruba as outras, e uma execução sobrevive a um reinício.

## Por onde começar

- **Nunca usou o Heddle?** [Instale](/pt/docs/start/installation/) e [monte seu primeiro fluxo](/pt/docs/start/first-flow/). Leva uns dez minutos.
- **Quer ver o que ele faz?** Os [tutoriais](/pt/docs/tutorials/webhook-to-slack/) montam fluxos reais de ponta a ponta, cada um com um arquivo para importar.
- **Procurando um nó?** A [referência de nós](/pt/docs/nodes/) tem todos eles, com campos, saídas e o que cada um devolve.

## Como a documentação está organizada

| Seção | Para quando você quer |
| --- | --- |
| **Primeiros passos** | Instalar o Heddle e conhecer o editor. |
| **Tutoriais** | Montar um fluxo completo, passo a passo. |
| **Conceitos** | Entender como funcionam execuções, dados, versões e equipes. |
| **Guias** | Fazer uma coisa: conectar um serviço, tratar erros, depurar uma execução. |
| **Nós** | Consultar o que um nó recebe e o que devolve. |
| **Referência** | Usar a API, o servidor MCP, o comando `heddle` e as configurações. |
| **Hospedagem própria** | Rodar o Heddle em servidores e escalar. |

## As palavras que você vai ver

O editor e os nós estão em inglês, então os nomes deles aparecem assim nesta documentação.

- Um **fluxo** (flow) é um grafo de **nós** ligados por **conexões**. Cada nó faz uma coisa.
- Uma **execução** (run, execution) é uma passada pelo fluxo. Ela carrega um **contexto**, os dados que cada passo lê e aumenta. Veja [Dados numa execução](/pt/docs/concepts/context/).
- Um fluxo tem um **rascunho** (draft), que você edita, e **versões publicadas**, que a produção roda. Veja [Versões](/pt/docs/concepts/versions/).
- Um **workspace** guarda os fluxos, as execuções, as credenciais e as chaves de API de uma equipe. Veja [Workspaces e papéis](/pt/docs/concepts/workspaces/).
- Uma **credencial** guarda, criptografado, o que um nó precisa para acessar um serviço. Veja [Credenciais](/pt/docs/guides/credentials/).
