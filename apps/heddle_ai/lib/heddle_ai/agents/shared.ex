defmodule HeddleAI.Agents.Shared do
  def nodes_description do
    node_definitions()
    |> Enum.map(fn node ->
      """
      - Type: #{node.name}
        Category: #{node.category}
        Inputs: #{inspect(node[:inputs] || [])}
        Outputs: #{inspect(node[:outputs] || [])}
        Description: #{node[:description] || "A node to perform #{node.name} operations."}
        Controls: #{controls_description(node)}
      """
    end)
    |> Enum.join("\n")
  end

  defp controls_description(node) do
    case node[:ui_fields] || [] do
      [] -> "none"
      fields -> Enum.map_join(fields, "; ", &control_description/1)
    end
  end

  defp control_description(field) do
    options = Enum.map_join(field[:options] || [], ", ", &option_value/1)

    "`#{field.name}` (#{field[:label]})" <> if(options == "", do: "", else: ": #{options}")
  end

  defp option_value(%{value: value}), do: to_string(value)
  defp option_value(value), do: to_string(value)

  defp node_definitions do
    module = Module.concat([HeddleNodes, Nodes])

    if Code.ensure_loaded?(module) do
      apply(module, :all_nodes, [])
    else
      []
    end
  end

  def current_flow_description(nil), do: ""

  def current_flow_description(current_flow) do
    """
    **CURRENT FLOW STATE:**
    Nodes: #{current_flow.nodes |> List.wrap() |> Enum.map(&Map.delete(&1, "position")) |> Jason.encode!()}
    Connections: #{current_flow.connections |> List.wrap() |> Enum.map(&Map.delete(&1, "targetInput")) |> Jason.encode!()}

    Use this state as the baseline for any modifications. If the user asks to "add" or "change" something, you must generate the FULL new flow JSON including existing nodes/connections plus your changes.
    """
  end

  def flow_generation_rules do
    """
    **JSON OUTPUT FORMAT FOR FLOW CREATION:**

    The JSON structure must be:

    {
      "action": "create_flow",
      "nodes": [
        {
          "id": "unique_id_1",
          "type": "Node Name (must match exactly from Available Nodes)",
          "label": "Custom Label",
          "controls": {
             "code_elixir": "...",
             "code_python": "...",
             "language": "elixir"
          }
        },
        ...
      ],
      "connections": [
        {
          "source": "unique_id_1",
          "sourceOutput": "output_name",
          "target": "unique_id_2"
        },
        ...
      ]
    }

    #{node_rules()}
    """
  end

  @doc "How flows work, for anything that builds them."
  def node_rules do
    """
    **IMPORTANT RULES FOR FLOW GENERATION:**
    -   **PREFER MODIFYING EXISTING NODES** over creating new ones if the request is a simple logic change.
    -   **CRITICAL:** A node only reads the controls listed for it. NEVER invent a control: it would be ignored.
    -   **Controls for "Condition"**: it compares the context value named in `variable` with `value`, using `operator`. It takes no code, so to test something computed, put an `Evaluate Code` before it and compare `result`.
    -   **CRITICAL: Use "type" instead of "name"** for the node type.
    -   **CRITICAL: Controls for "Evaluate Code"**: Must include `code_elixir`, `code_python`, and `language`.
    -   **CRITICAL: Controls for "Output"**: Must include `status`.
    -   **Variable Usage in Eval Nodes**:
        -   What the flow was called with is in the context: `variable(:name)` reads a field of the input of the run, and `variable(:body)["name"]`, `variable(:headers)` and `variable(:query_params)` read the request of a `Webhook`.
        -   `input` only exists in a step an `AI Agent` calls as a tool. NEVER use it anywhere else.
        -   The result of the previous node is available directly as `result`.
        -   Use `variable(:atom_name)` to access other context variables.
        -   **CRITICAL:** Do NOT assign to `result`. Just write the expression.
    -   Use unique string IDs for nodes.
    -   Ensure `sourceOutput` is one of the outputs of the source node.
    -   Connections leaving the same output run one after the other, in the order you list them.
    -   The canvas places the nodes, so don't send a position.
    -   A comment of kind `section` groups the nodes listed in its `nodes`. With `manual: true` they don't run with the flow: a branch that reaches one stops there, and they run only when a run is given that `section_id`. NEVER change them: the person sets them on the canvas.
    -   **CRITICAL:** A flow begins at exactly ONE entry node, which has no inputs: a `Webhook` when an HTTP call triggers the flow, a `Schedule` when it runs on a timetable, a `Form Trigger` when people fill in a form, otherwise a `Start`. NEVER use more than one, and NEVER connect anything into an entry node.
    -   **Controls for "Schedule"**: `cron` is a five-field cron expression in UTC, like `0 9 * * 1-5`.
    -   **Controls for "Form Trigger"**: `title`, `description`, `submit_label`, `success_message`, `redirect_url`, `accepting` (`yes` or `no`) and `fields`, which is JSON TEXT of a list like `[{"key": "email", "label": "Email", "type": "email", "required": true}]`. A field's `type` is `text`, `textarea`, `email`, `number`, `date`, `select` (with `options`, a list of texts) or `checkbox`, and its `key` is letters, digits and `_`. Anyone with the form's link can send it once the flow is published, and what they sent is in `{{form.<key>}}` and in `result`.
    -   **Spool nodes**: `Spool: Insert Rows`, `Spool: Find Rows`, `Spool: Update Rows`, `Spool: Upsert Rows` and `Spool: Delete Rows` read and write the tables Heddle keeps itself, with no credential. `table` is the name of a table: call list_spool_tables for the names of tables and columns, and NEVER invent them. `rows` is one object or a list, from column name to value, like `{{form}}`. `filter` is an object from column to value or to operators, like `{"email": "{{form.email}}"}` or `{"total": {">": 100}}`. Update and Delete need a filter.
    -   **Controls for "AI Agent"**: `prompt`, and optionally `system`, `output` (`text` or `json`) and `memory_key`, which remembers the conversation between runs. They accept `{{name}}` placeholders. Its reply goes to `result`, through the `success` output. Connect the `error` output when a failure must be handled. Nodes connected to its `tools` output are steps it can choose to use, and it fills in the fields left blank on them, so leave blank what it should decide.
    -   **Credentials**: the `Slack: ...`, `Email: ...`, `Google Sheets: ...`, `S3: ...`, `FTP: ...` nodes and the database nodes, one per action, take a `credential` control with the name of a stored credential. NEVER put a token or password in a node. If you don't know the name, leave it blank and tell the user to pick one.
    -   **Database nodes**: `SQL: ...` work on PostgreSQL, MySQL, MariaDB, SQL Server, SQLite and Oracle, and the credential picks which. `MongoDB: ...`, `Redis: ...`, `Elasticsearch: ...`, `DynamoDB: ...`, `Cassandra: ...` and `Neo4j: ...` each work on that store. Results go to `result`, like `result.rows` or `result.documents`. In a query, write `{{name}}` without quotes around it: it goes to the database as a parameter, so NEVER build a query by joining text, and NEVER put a placeholder in the name of a table or column. Fields with JSON take placeholders the same way, like `{"name": {{body.name}}}`. Connect the `error` output when a failure must be handled.
    -   **AI nodes**: besides `AI Agent`, use the `AI: ...` nodes for one task, like `AI: Generate Image` or `AI: Summarize`. Leave their `credential` and `model` controls blank so they use the defaults of the AI page. Only set them to values the user gave you: a made-up model makes the node fail.
    -   **Controls for "For Each"**: `items` is the path of the list, like `result` or `body.items`. Connect what runs per item to the `item` output and what comes after to the `done` output, which receives the list of results in `result`. Inside the branch, `result` is the item and `variable(:index)` its position. The branch ends at its last node: NEVER connect it back into the `For Each`, and NEVER connect it to what comes after. Only the `done` output continues the flow.
    -   **Controls for "Switch"**: `switch_value`, like `{{body.status}}`, and `case_1` to `case_4`. The run goes down the output of the first case equal to the value (`case 1` to `case 4`), or down `otherwise`. Leave unused cases blank. For more than four, connect another `Switch` to `otherwise`.
    -   **Controls for "Merge"**: `combine`: `list` (the default) gives `result` as the list of each branch's result, in the order they arrived, `concat` joins lists into one, and `objects` merges maps into one. It waits for every connection into it and then goes on once, so connect the end of each branch to it when they must all finish before the next step. A branch a `Condition` or `Switch` never took doesn't hold it forever.
    -   **Controls for "Wait"**: `wait_for` is `time` (with `amount` and `unit`: `seconds`, `minutes`, `hours` or `days`), `date` (with `wait_until`, an ISO 8601 date in UTC) or `call`. With `call`, it waits until the address `{{resume_url}}` is called, so send that address first, like in a message asking for an approval. Its `result` is then the call, with `body`, `query_params` and `method`, and `amount` with `unit` is the most it waits, after which the run goes on through the `timeout` output. Leave `amount` blank to wait for as long as it takes. A run that waits holds nothing: it is saved and goes on by itself.
    -   **Settings**: besides `controls`, a node may have `settings`, for how it behaves when it fails. `retries` (0 to 10) runs it again that many times, `retry_delay` is the seconds before each new try, and `retry_backoff: "exponential"` doubles that wait each time: use them on nodes that call a service that can be briefly down. `on_error` is `stop` (the default: the `error` output if connected, otherwise the run fails), `continue` (it goes on through its usual output with `{"error": message}` as `result`) or `output` (it gives any node an `error` output to connect). Keep the `settings` a node already has, including `pin`, which the person sets.
    -   **Error flows**: a flow that starts with an `Error Trigger` runs when another flow that picked it as its error flow fails. Its context has `error` (`message`, `node_id`, `node_label`, `node_type`) and `execution` (`id`, `flow_name`, `url`).
    -   **Controls for "Respond to Webhook"**: `response_status` and `response_body`, which accepts `{{name}}` placeholders. Use it when the caller of a `Webhook` needs an answer.
    -   **CRITICAL:** End the flow with an `Output` node.
    """
  end

  def example_json do
    """
    **EXAMPLE:**
    User: "Create a flow that adds 5 + 5 and then adds 10."
    Assistant:
    {
      "action": "create_flow",
      "nodes": [
        {
          "id": "node_1",
          "type": "Start",
          "label": "Start",
          "controls": {}
        },
        {
          "id": "node_2",
          "type": "Evaluate Code",
          "label": "Add 5 + 5",
          "controls": { "code_elixir": "5 + 5", "language": "elixir", "code_python": "" }
        },
        {
          "id": "node_3",
          "type": "Evaluate Code",
          "label": "Add 10 more",
          "controls": { "code_elixir": "result + 10", "language": "elixir", "code_python": "" }
        },
        {
          "id": "node_4",
          "type": "Output",
          "label": "Result",
          "controls": { "status": "success" }
        }
      ],
      "connections": [
        {
          "source": "node_1",
          "sourceOutput": "exec",
          "target": "node_2"
        },
        {
          "source": "node_2",
          "sourceOutput": "exec",
          "target": "node_3"
        },
        {
          "source": "node_3",
          "sourceOutput": "exec",
          "target": "node_4"
        }
      ]
    }
    """
  end
end
