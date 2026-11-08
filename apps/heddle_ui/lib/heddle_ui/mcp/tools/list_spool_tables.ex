defmodule HeddleUI.MCP.Tools.ListSpoolTables do
  @moduledoc """
  Lists the Spool tables of the workspace, the tables Heddle keeps itself: each one's
  name, its columns with their types, and how many rows it has. The Spool nodes find
  a table by its name and a column by its name, so use these names in their fields.
  Column types are text, number, boolean, date and json. Rows also have id,
  created_at and updated_at. A filter of a Spool node is an object from column to
  value, or to operators: {"total": {">": 100}}, {"name": {"contains": "ana"}},
  {"phone": {"empty": true}}, {"id": {"in": [1, 2]}}. Reading or writing rows is
  what a flow does, with the Spool nodes.
  """

  use Anubis.Server.Component,
    type: :tool,
    name: "list_spool_tables",
    annotations: %{readOnlyHint: true}

  alias HeddleCore.Spool
  alias HeddleUI.MCP.Tool

  schema do
  end

  @impl true
  def execute(_params, frame) do
    Tool.authorize(frame, "workflows:read", fn scope ->
      scope
      |> Spool.list_tables()
      |> Enum.map(fn table ->
        %{
          name: table.name,
          rows: table.row_count,
          columns: Enum.map(table.columns, &%{name: &1["name"], type: &1["type"]})
        }
      end)
      |> then(&Tool.reply(%{tables: &1}, frame))
    end)
  end
end
