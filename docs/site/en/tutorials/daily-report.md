---
title: A daily report by email
description: Every weekday morning, read yesterday's orders from the database, turn them into a CSV and email it to the team.
sidebar:
  order: 2
---

Every weekday at 08:00 in São Paulo, Heddle reads yesterday's orders, writes them into a CSV and emails it to the sales team. If the database is down, it says so on Slack.

**You will use** [Schedule](/docs/nodes/schedule/), [SQL: Select Rows](/docs/nodes/sql-select-rows/), [Write CSV](/docs/nodes/write-csv/), [Email: Send Email](/docs/nodes/email-send-email/), [Slack: Send Message](/docs/nodes/slack-send-message/). **Import it:** [daily-report.json](/docs/examples/daily-report.json).

## Before you start

Create three credentials: a **SQL database** one for the database with the orders, an **Email (SMTP)** one, and a **Slack** one. See [Credentials](/docs/guides/credentials/).

The tutorial assumes an `orders` table with `id`, `customer`, `total` and `created_at`. Change the names to yours.

## 1. Run every weekday

Add a **Schedule** with **Cron** `0 11 * * 1-5`. Cron runs in UTC, and 11:00 UTC is 08:00 in São Paulo. `1-5` is Monday to Friday.

## 2. Read yesterday's orders

Add a **SQL: Select Rows**:

| Field | Value |
| --- | --- |
| Table | `orders` |
| Columns | `id, customer, total, created_at` |
| Where | `created_at >= CURRENT_DATE - 1 AND created_at < CURRENT_DATE` |
| Order by | `created_at` |
| Limit | `5000` |

It returns `result.rows`, a list of objects, and `result.count`.

## 3. Turn them into a CSV

Add a **Write CSV** on the `success` output, with **Source** `result.rows`. Its `result` is the CSV text, with a header line.

## 4. Email it

Add an **Email: Send Email** after it:

| Field | Value |
| --- | --- |
| To | `sales@example.com` |
| Subject | `Orders of yesterday` |
| Message | `Good morning! Yesterday's orders are attached.` |
| Attachment name | `orders.csv` |
| Attachment content | `{{result}}` |

## 5. Say when it fails

Add a **Slack: Send Message** on the `error` output of the SQL node, with **Message** `The daily orders report failed: {{result.error}}`.

## 6. Try it and publish

Press **Run Flow**: a Schedule doesn't wait for its time when you run from the editor. Check the email, then **Publish**. Schedules run only the published version.

## Go further

- Many rows? Use **Offset** and a [For Each](/docs/nodes/for-each/), or a SQL query that sums them up with [SQL: Run Query](/docs/nodes/sql-run-query/).
- Write the numbers into a sheet with [Google Sheets: Add Rows](/docs/nodes/google-sheets-add-rows/), or keep the file with [S3: Upload File](/docs/nodes/s3-upload-file/).
- Add a summary written by AI: an [AI: Summarize](/docs/nodes/ai-summarize/) on `{{result}}` before the email.
