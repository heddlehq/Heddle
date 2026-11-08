---
title: Spool
description: Keep tables inside Heddle, with nothing to set up, and read and write them from flows.
sidebar:
  order: 4
---

Spool is the database Heddle keeps for each workspace. There is nothing to install and no credential to create: a flow can keep the answers of a form, a list of customers to follow up, or what it needs to remember between runs.

Open **Spool** in the sidebar to see the tables of the workspace.

## Tables and columns

A table has a name, unique in its workspace, and columns. Each column has a name and a type:

| Type | Holds | Also takes |
| --- | --- | --- |
| Text | Any text | Numbers and booleans become text, lists and objects JSON |
| Number | An integer or a decimal | Text like `"12.5"` |
| Yes / no | `true` or `false` | `"yes"`, `"no"`, `"on"`, `"off"`, `"1"`, `"0"` |
| Date | A date or a moment, as ISO 8601 | `2026-11-08`, `2026-11-08T10:00:00Z` |
| JSON | Any value | |

Every row also has an `id`, `created_at` and `updated_at`.

Change the columns in the **Columns** tab. Renaming a column keeps its values. Changing its type converts every value: if one can't be converted, nothing changes and Heddle says which rows. Removing a column deletes its values.

In the **Rows** tab you search, add, change and delete rows, and **Export CSV** downloads the table.

## In a flow

Five nodes read and write a table, found by its name:

| Node | Does |
| --- | --- |
| [Spool: Insert Rows](/docs/nodes/spool-insert-rows/) | Adds one row or a list of them |
| [Spool: Find Rows](/docs/nodes/spool-find-rows/) | Reads the rows that match a filter, in order |
| [Spool: Update Rows](/docs/nodes/spool-update-rows/) | Changes the rows that match a filter |
| [Spool: Upsert Rows](/docs/nodes/spool-upsert-rows/) | Changes the row with the same key, or adds one |
| [Spool: Delete Rows](/docs/nodes/spool-delete-rows/) | Deletes the rows that match a filter |

A row goes in as an object from column name to value, like `{"email": "{{form.email}}", "score": 10}`, or a single placeholder like `{{form}}`. An unknown column or a value of the wrong type fails the node through its `error` output, and none of the rows go in.

## Filters

A filter is an object from column to what it must be:

```json
{
  "status": "open",
  "total": {">": 100, "<=": 500},
  "name": {"contains": "ana"},
  "phone": {"empty": true},
  "id": {"in": [1, 2, 3]}
}
```

Every condition must hold. The operators are `=`, `!=`, `>`, `>=`, `<`, `<=`, `contains` (text inside, ignoring case), `empty` and `in`. A placeholder is always a value, sent to the database as a parameter, so what a form sends can't change what the filter does. Update and Delete need a filter, so a mistake doesn't change every row.

**Order by** takes column names, each with `asc` or `desc`, like `total desc, name`.

## Who can do what

Viewers and operators see tables and rows. Editors create tables, change columns and change rows. Only admins delete a table. A run reaches only the tables of its flow's workspace.

## Limits

A workspace keeps up to 50 tables, a table up to 100,000 rows, and a row up to 64 KB. A search returns up to 1,000 rows. Whoever runs Heddle can change these, see [Configuration](/docs/reference/configuration/).
