---
title: Spool
description: Guarde tabelas dentro do Heddle, sem configurar nada, e leia e escreva nelas pelos fluxos.
sidebar:
  order: 4
---

O Spool é o banco de dados que o Heddle mantém para cada workspace. Não há nada para instalar nem credencial para criar: um fluxo pode guardar as respostas de um formulário, uma lista de clientes para retornar, ou o que precisa lembrar entre execuções.

Abra **Spool** na barra lateral para ver as tabelas do workspace.

## Tabelas e colunas

Uma tabela tem um nome, único no workspace, e colunas. Cada coluna tem um nome e um tipo:

| Tipo | Guarda | Também aceita |
| --- | --- | --- |
| Texto | Qualquer texto | Números e booleanos viram texto, listas e objetos viram JSON |
| Número | Um inteiro ou um decimal | Texto como `"12.5"` |
| Sim / não | `true` ou `false` | `"yes"`, `"no"`, `"sim"`, `"on"`, `"off"`, `"1"`, `"0"` |
| Data | Uma data ou um momento, em ISO 8601 | `2026-11-08`, `2026-11-08T10:00:00Z` |
| JSON | Qualquer valor | |

Toda linha também tem `id`, `created_at` e `updated_at`.

Mude as colunas na aba **Colunas**. Renomear uma coluna mantém os valores. Mudar o tipo converte todos os valores: se algum não puder ser convertido, nada muda e o Heddle diz quais linhas. Remover uma coluna apaga os valores dela.

Na aba **Linhas** você busca, adiciona, altera e apaga linhas, e **Exportar CSV** baixa a tabela.

## Num fluxo

Cinco nós leem e escrevem numa tabela, encontrada pelo nome:

| Nó | Faz |
| --- | --- |
| [Spool: Insert Rows](/pt/docs/nodes/spool-insert-rows/) | Adiciona uma linha ou uma lista delas |
| [Spool: Find Rows](/pt/docs/nodes/spool-find-rows/) | Lê as linhas que batem com um filtro, em ordem |
| [Spool: Update Rows](/pt/docs/nodes/spool-update-rows/) | Altera as linhas que batem com um filtro |
| [Spool: Upsert Rows](/pt/docs/nodes/spool-upsert-rows/) | Altera a linha com a mesma chave, ou adiciona uma |
| [Spool: Delete Rows](/pt/docs/nodes/spool-delete-rows/) | Apaga as linhas que batem com um filtro |

Uma linha entra como um objeto do nome da coluna para o valor, como `{"email": "{{form.email}}", "score": 10}`, ou um único placeholder como `{{form}}`. Uma coluna desconhecida ou um valor do tipo errado faz o nó sair pela saída `error`, e nenhuma linha entra.

## Filtros

Um filtro é um objeto da coluna para o que ela precisa ser:

```json
{
  "status": "open",
  "total": {">": 100, "<=": 500},
  "name": {"contains": "ana"},
  "phone": {"empty": true},
  "id": {"in": [1, 2, 3]}
}
```

Todas as condições precisam valer. Os operadores são `=`, `!=`, `>`, `>=`, `<`, `<=`, `contains` (texto contido, sem diferenciar maiúsculas), `empty` e `in`. Um placeholder é sempre um valor, enviado ao banco como parâmetro, então o que um formulário envia não muda o que o filtro faz. Update e Delete exigem um filtro, para um engano não alterar todas as linhas.

**Order by** recebe nomes de colunas, cada um com `asc` ou `desc`, como `total desc, name`.

## Quem pode o quê

Viewers e operators veem tabelas e linhas. Editors criam tabelas, mudam colunas e alteram linhas. Só admins apagam uma tabela. Uma execução só alcança as tabelas do workspace do seu fluxo.

## Limites

Um workspace guarda até 50 tabelas, uma tabela até 100.000 linhas, e uma linha até 64 KB. Uma busca devolve até 1.000 linhas. Quem administra o Heddle pode mudar esses valores, veja [Configuração](/pt/docs/reference/configuration/).
