---
title: Credentials
description: Store what nodes need to reach Slack, email, Google Sheets, S3, FTP, databases and AI providers, encrypted.
sidebar:
  order: 1
---

A credential holds what a node needs to reach a service: a token, a password, a key. Create them in **Credentials**, then pick one in the node's **Credential** field.

- Values are encrypted with a key derived from the server's `SECRET_KEY_BASE`. A flow keeps only the credential's name, so exporting a flow, or reading its run, never shows a secret.
- A credential belongs to a workspace, and only its flows use it. A system admin can create **shared** credentials, which every workspace can use but nobody else can change.
- Editors and admins create and change credentials. See [Workspaces and roles](/docs/concepts/workspaces/#credentials).
- Deleting a credential stops every flow that uses it, so the page asks first.

## Slack

**Bot token**, which starts with `xoxb-`.

1. Create an app at [api.slack.com/apps](https://api.slack.com/apps), **From scratch**.
2. In **OAuth & Permissions**, add the bot scopes the nodes you use need: `chat:write` to send, update and delete messages, `channels:history` and `groups:history` to read them, `reactions:write`, `files:write`, and `channels:read` and `groups:read` to list channels.
3. **Install to Workspace**, and copy the **Bot User OAuth Token**.
4. Invite the app to each channel it works in: `/invite @your-app`.

## Email

Sending and reading are two credentials.

**Email (SMTP)**, to send: **Host**, **Port** (587 by default), **Username**, **Password** and **From address**. With Gmail, use `smtp.gmail.com` and an [app password](https://myaccount.google.com/apppasswords), not your own.

**Email (IMAP)**, to read: **Host**, **Port** (993) and the account's **Username** and **Password**. It only connects over TLS. With Gmail, `imap.gmail.com` and an app password.

## Google Sheets

**Service account JSON**, the key of a Google Cloud service account.

1. In the [Google Cloud console](https://console.cloud.google.com/), create a project and turn on the **Google Sheets API**.
2. In **IAM & Admin → Service accounts**, create one, open **Keys**, and add a JSON key. Paste the whole file.
3. Share each spreadsheet with the service account's email, like `heddle@my-project.iam.gserviceaccount.com`, as an editor.

## S3

**Access key ID**, **Secret access key**, **Region** and, for services other than AWS, **Endpoint**.

| Service | Endpoint | Region |
| --- | --- | --- |
| AWS S3 | blank | Your bucket's, like `us-east-1` |
| Cloudflare R2 | `https://<account id>.r2.cloudflarestorage.com` | `auto` |
| MinIO | Your server, like `https://minio.example.com` | `us-east-1` |
| DigitalOcean Spaces | `https://<region>.digitaloceanspaces.com` | Like `nyc3` |
| Backblaze B2 | `https://s3.<region>.backblazeb2.com` | Like `us-west-004` |

Give the key only the buckets and actions the flows need.

## FTP

**Host**, **Port** (21), **Username** and **Password**. Paths in the FTP nodes start from the folder this account starts in.

## Databases

Each database has its own credential: **SQL database** (PostgreSQL, MySQL, MariaDB, SQL Server, Oracle, SQLite), **MongoDB**, **Redis**, **Elasticsearch or OpenSearch**, **DynamoDB**, **Cassandra or ScyllaDB** and **Neo4j**. The form says what each needs, and [Databases](/docs/guides/databases/) explains them.

## AI provider

**Provider** (Google, OpenAI, Anthropic or xAI) and **API key**. See [AI providers](/docs/guides/ai-providers/).

## If the server's secret changes

Every credential is encrypted with `SECRET_KEY_BASE`. If it changes, they all stop working and have to be entered again, so back it up with your data, and give the UI and the workers the same one.
