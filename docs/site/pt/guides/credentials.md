---
title: Credenciais
description: Guarde, criptografado, o que os nós precisam para acessar Slack, email, Google Sheets, S3, FTP, bancos de dados e provedores de IA.
sidebar:
  order: 1
---

Uma credencial guarda o que um nó precisa para acessar um serviço: um token, uma senha, uma chave. Crie em **Credentials** e escolha no campo **Credential** do nó.

- Os valores são criptografados com uma chave derivada do `SECRET_KEY_BASE` do servidor. Um fluxo guarda só o nome da credencial, então exportar um fluxo, ou ler uma execução, nunca mostra um segredo.
- Uma credencial pertence a um workspace, e só os fluxos dele usam. Um admin do sistema pode criar credenciais **compartilhadas**, que todo workspace usa mas ninguém mais muda.
- Editores e admins criam e mudam credenciais. Veja [Workspaces e papéis](/pt/docs/concepts/workspaces/#credenciais).
- Apagar uma credencial para todo fluxo que a usa, então a página pergunta antes.

## Slack

**Bot token**, que começa com `xoxb-`.

1. Crie um app em [api.slack.com/apps](https://api.slack.com/apps), **From scratch**.
2. Em **OAuth & Permissions**, adicione os escopos de bot que os nós que você usa precisam: `chat:write` para mandar, editar e apagar mensagens, `channels:history` e `groups:history` para ler, `reactions:write`, `files:write`, e `channels:read` e `groups:read` para listar canais.
3. **Install to Workspace**, e copie o **Bot User OAuth Token**.
4. Convide o app para cada canal em que ele trabalha: `/invite @seu-app`.

## Email

Mandar e ler são duas credenciais.

**Email (SMTP)**, para mandar: **Host**, **Port** (587 por padrão), **Username**, **Password** e **From address**. No Gmail, use `smtp.gmail.com` e uma [senha de app](https://myaccount.google.com/apppasswords), não a sua.

**Email (IMAP)**, para ler: **Host**, **Port** (993) e o **Username** e **Password** da conta. Só conecta por TLS. No Gmail, `imap.gmail.com` e uma senha de app.

## Google Sheets

**Service account JSON**, a chave de uma conta de serviço do Google Cloud.

1. No [console do Google Cloud](https://console.cloud.google.com/), crie um projeto e ligue a **Google Sheets API**.
2. Em **IAM & Admin → Service accounts**, crie uma, abra **Keys** e adicione uma chave JSON. Cole o arquivo inteiro.
3. Compartilhe cada planilha com o email da conta de serviço, como `heddle@meu-projeto.iam.gserviceaccount.com`, como editor.

## S3

**Access key ID**, **Secret access key**, **Region** e, para serviços que não são a AWS, **Endpoint**.

| Serviço | Endpoint | Region |
| --- | --- | --- |
| AWS S3 | em branco | A do seu bucket, como `sa-east-1` |
| Cloudflare R2 | `https://<account id>.r2.cloudflarestorage.com` | `auto` |
| MinIO | Seu servidor, como `https://minio.example.com` | `us-east-1` |
| DigitalOcean Spaces | `https://<região>.digitaloceanspaces.com` | Como `nyc3` |
| Backblaze B2 | `https://s3.<região>.backblazeb2.com` | Como `us-west-004` |

Dê à chave só os buckets e as ações de que os fluxos precisam.

## FTP

**Host**, **Port** (21), **Username** e **Password**. Os caminhos dos nós de FTP partem da pasta em que essa conta começa.

## Bancos de dados

Cada banco tem a sua credencial: **SQL database** (PostgreSQL, MySQL, MariaDB, SQL Server, Oracle, SQLite), **MongoDB**, **Redis**, **Elasticsearch or OpenSearch**, **DynamoDB**, **Cassandra or ScyllaDB** e **Neo4j**. O formulário diz o que cada uma pede, e [Bancos de dados](/pt/docs/guides/databases/) explica.

## Provedor de IA

**Provider** (Google, OpenAI, Anthropic ou xAI) e **API key**. Veja [Provedores de IA](/pt/docs/guides/ai-providers/).

## Se o segredo do servidor mudar

Toda credencial é criptografada com o `SECRET_KEY_BASE`. Se ele mudar, todas param de funcionar e precisam ser cadastradas de novo, então faça backup dele junto com os dados, e dê o mesmo para a interface e os workers.
