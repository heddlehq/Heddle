---
title: Um relatório diário por email
description: Todo dia útil de manhã, leia os pedidos de ontem no banco, transforme num CSV e mande por email para o time.
sidebar:
  order: 2
---

Todo dia útil às 08:00 de São Paulo, o Heddle lê os pedidos de ontem, escreve num CSV e manda por email para o time de vendas. Se o banco estiver fora, ele avisa no Slack.

**Você vai usar** [Schedule](/pt/docs/nodes/schedule/), [SQL: Select Rows](/pt/docs/nodes/sql-select-rows/), [Write CSV](/pt/docs/nodes/write-csv/), [Email: Send Email](/pt/docs/nodes/email-send-email/), [Slack: Send Message](/pt/docs/nodes/slack-send-message/).

<!-- flow:daily-report -->

## Antes de começar

Crie três credenciais: uma de **SQL database** para o banco dos pedidos, uma de **Email (SMTP)** e uma do **Slack**. Veja [Credenciais](/pt/docs/guides/credentials/).

O tutorial supõe uma tabela `orders` com `id`, `customer`, `total` e `created_at`. Troque pelos seus nomes.

## 1. Rode todo dia útil

Adicione um **Schedule** com **Cron** `0 11 * * 1-5`. O cron roda em UTC, e 11:00 UTC é 08:00 em São Paulo. `1-5` é de segunda a sexta.

## 2. Leia os pedidos de ontem

Adicione um **SQL: Select Rows**:

| Campo | Valor |
| --- | --- |
| Table | `orders` |
| Columns | `id, customer, total, created_at` |
| Where | `created_at >= CURRENT_DATE - 1 AND created_at < CURRENT_DATE` |
| Order by | `created_at` |
| Limit | `5000` |

Ele devolve `result.rows`, uma lista de objetos, e `result.count`.

## 3. Transforme num CSV

Adicione um **Write CSV** na saída `success`, com **Source** `result.rows`. O `result` dele é o texto do CSV, com a linha de cabeçalho.

## 4. Mande por email

Adicione um **Email: Send Email** depois dele:

| Campo | Valor |
| --- | --- |
| To | `vendas@example.com` |
| Subject | `Pedidos de ontem` |
| Message | `Bom dia! Os pedidos de ontem estão em anexo.` |
| Attachment name | `pedidos.csv` |
| Attachment content | `{{result}}` |

## 5. Avise quando falhar

Adicione um **Slack: Send Message** na saída `error` do nó de SQL, com **Message** `O relatório diário de pedidos falhou: {{result.error}}`.

## 6. Teste e publique

Aperte **Run Flow**: rodando pelo editor, o Schedule não espera o horário. Confira o email e **Publish**. Os agendamentos só rodam a versão publicada.

## Indo além

- Muitas linhas? Use **Offset** e um [For Each](/pt/docs/nodes/for-each/), ou uma consulta que resume tudo com [SQL: Run Query](/pt/docs/nodes/sql-run-query/).
- Escreva os números numa planilha com [Google Sheets: Add Rows](/pt/docs/nodes/google-sheets-add-rows/), ou guarde o arquivo com [S3: Upload File](/pt/docs/nodes/s3-upload-file/).
- Inclua um resumo escrito por IA: um [AI: Summarize](/pt/docs/nodes/ai-summarize/) sobre `{{result}}` antes do email.
