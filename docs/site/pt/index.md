---
title: Documentação do Heddle
description: Monte, rode e publique automações num canvas visual, com IA, código e os serviços que você usa.
template: splash
sidebar:
  label: Visão geral
  order: 0
hero:
  title: Desenhe uma vez. O Heddle roda.
  tagline: Tudo sobre montar fluxos no canvas, rodar no seu próprio servidor e conectar às ferramentas que você usa.
  image:
    html: '<!-- flow-art:support-triage -->'
  actions:
    - text: Monte seu primeiro fluxo
      link: start/first-flow/
      icon: right-arrow
    - text: Veja os nós
      link: nodes/
      variant: minimal
---

## Comece aqui

<div class="docs-cards docs-cards-3">
<a class="docs-card" href="/pt/docs/start/installation/"><span class="docs-card-icon"><!-- icon:hero-arrow-down-tray --></span><strong>Instale o Heddle</strong><span>Um comando no seu computador, ou Docker num servidor.</span></a>
<a class="docs-card" href="/pt/docs/start/first-flow/"><span class="docs-card-icon"><!-- icon:hero-play --></span><strong>Seu primeiro fluxo</strong><span>Chame uma API, formate a resposta, rode e veja por dentro. Dez minutos.</span></a>
<a class="docs-card" href="/pt/docs/start/editor/"><span class="docs-card-icon"><!-- icon:hero-squares-2x2 --></span><strong>O editor</strong><span>O canvas, a gaveta do nó, o inspetor de execuções e o chat de IA.</span></a>
</div>

## Monte algo de verdade

<div class="docs-cards docs-cards-2">
<a class="docs-card docs-card-wide" href="/pt/docs/tutorials/webhook-to-slack/"><span class="docs-card-icon"><!-- icon:hero-bolt --></span><strong>Webhook para o Slack</strong><span>Receba leads de um formulário e avise o time de vendas.</span></a>
<a class="docs-card docs-card-wide" href="/pt/docs/tutorials/daily-report/"><span class="docs-card-icon"><!-- icon:hero-envelope --></span><strong>Um relatório diário por email</strong><span>Leia os pedidos de ontem, gere um CSV e mande toda manhã.</span></a>
<a class="docs-card docs-card-wide" href="/pt/docs/tutorials/support-triage/"><span class="docs-card-icon"><!-- icon:hero-sparkles --></span><strong>Triagem de suporte com IA</strong><span>A IA lê cada chamado e manda para o time certo.</span></a>
<a class="docs-card docs-card-wide" href="/pt/docs/tutorials/refund-approval/"><span class="docs-card-icon"><!-- icon:hero-hand-raised --></span><strong>Reembolsos com aprovação</strong><span>Pause uma execução até alguém aprovar no Slack.</span></a>
</div>

## Vá mais fundo

<div class="docs-columns">
<div class="docs-column"><p class="docs-column-title"><!-- icon:hero-light-bulb -->Conceitos</p><a href="/pt/docs/concepts/context/">Dados numa execução</a><a href="/pt/docs/concepts/runs/">Como uma execução anda</a><a href="/pt/docs/concepts/versions/">Rascunhos e versões</a><a href="/pt/docs/concepts/collaboration/">Edição em grupo</a><a href="/pt/docs/concepts/workspaces/">Workspaces e papéis</a></div>
<div class="docs-column"><p class="docs-column-title"><!-- icon:hero-wrench-screwdriver -->Guias</p><a href="/pt/docs/guides/credentials/">Credenciais</a><a href="/pt/docs/guides/starting-flows/">Disparando fluxos</a><a href="/pt/docs/guides/error-handling/">Tratando erros</a><a href="/pt/docs/guides/debugging/">Depurando uma execução</a><a href="/pt/docs/guides/ai-agent/">O AI Agent e o chat</a></div>
<div class="docs-column"><p class="docs-column-title"><!-- icon:hero-book-open -->Referência</p><a href="/pt/docs/nodes/">Os 103 nós</a><a href="/pt/docs/reference/api/">API REST</a><a href="/pt/docs/reference/mcp/">Servidor MCP</a><a href="/pt/docs/reference/cli/">O comando heddle</a><a href="/pt/docs/reference/configuration/">Configuração</a></div>
</div>

## As palavras que você vai ver

O editor e os nós estão em inglês, então os nomes deles aparecem assim nesta documentação.

- Um **fluxo** (flow) é um grafo de **nós** ligados por **conexões**. Cada nó faz uma coisa.
- Uma **execução** (run) é uma passada pelo fluxo. Ela carrega um **contexto**, os dados que cada passo lê e aumenta. Veja [Dados numa execução](/pt/docs/concepts/context/).
- Um fluxo tem um **rascunho** (draft), que você edita, e **versões publicadas**, que a produção roda. Veja [Rascunhos e versões](/pt/docs/concepts/versions/).
- Um **workspace** guarda os fluxos, as execuções, as credenciais e as chaves de API de uma equipe. Veja [Workspaces e papéis](/pt/docs/concepts/workspaces/).
- Uma **credencial** guarda, criptografado, o que um nó precisa para acessar um serviço. Veja [Credenciais](/pt/docs/guides/credentials/).
