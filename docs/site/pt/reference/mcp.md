---
title: Servidor MCP
description: Deixe o Claude Code, o Claude Desktop, o Cursor ou qualquer cliente MCP ler, montar, rodar e publicar seus fluxos.
sidebar:
  order: 2
---

O Heddle é um servidor [MCP](https://modelcontextprotocol.io). Uma ferramenta de IA conectada a ele ganha as mesmas ferramentas que o chat do editor tem: lista os nós, lê um fluxo, altera, testa e publica quando você manda.

## Conectar

O endereço é `/mcp` no seu Heddle, por HTTP, com uma [chave de API](/pt/docs/reference/api/#autenticação) no cabeçalho. A chave decide o workspace e o que a ferramenta pode fazer.

**Claude Code**:

```bash
claude mcp add --transport http heddle https://seu-heddle/mcp \
  --header "Authorization: Bearer <chave de API>"
```

**Clientes com configuração em JSON**, como o Claude Desktop ou o Cursor:

```json
{
  "mcpServers": {
    "heddle": {
      "type": "http",
      "url": "https://seu-heddle/mcp",
      "headers": {"Authorization": "Bearer <chave de API>"}
    }
  }
}
```

A página **AI** mostra o comando com o seu endereço preenchido. Numa instalação local, o **Terminal** do editor abre o Claude Code já conectado.

## Ferramentas

| Ferramenta | Faz |
| --- | --- |
| `list_nodes` | Lista todos os nós, com campos e saídas |
| `list_flows` | Lista os fluxos do workspace |
| `get_flow` | Lê um fluxo: nós, conexões e comentários |
| `create_flow` | Cria um fluxo; os nós sem posição são organizados sozinhos |
| `update_flow` | Substitui o nome, os nós ou as conexões de um fluxo; aparece na hora nos canvas abertos |
| `test_flow` | Roda o rascunho e espera, devolvendo o status, o erro, o contexto final e cada passo. Num fluxo de webhook, recebe o corpo da requisição |
| `run_flow` | Coloca uma execução do rascunho na fila e devolve o id |
| `list_executions` | Lista as execuções de um fluxo |
| `get_execution` | Lê uma execução |
| `list_versions` | Lista as versões, com quem fez cada uma e o que mudou |
| `publish_flow` | Publica o rascunho, ou coloca uma versão antiga de volta |
| `restore_version` | Coloca uma versão no rascunho |
| `chat` | Conversa com o próprio agente do Heddle, que responde com o modelo deste servidor |

`test_flow`, `run_flow`, `publish_flow` e `restore_version` mudam coisas de verdade. Um cliente bem-comportado pergunta antes de chamar.

## Um bom primeiro pedido

> Usando o Heddle, liste os nós e monte um fluxo que lê as linhas novas da planilha "Leads" a cada hora e manda cada uma para o #vendas no Slack. Teste antes de me dizer que terminou.

A ferramenta vai chamar `list_nodes`, `create_flow`, `test_flow`, ler o erro se houver, corrigir com `update_flow` e tentar de novo.
