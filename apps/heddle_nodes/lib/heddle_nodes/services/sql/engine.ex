defmodule HeddleNodes.Services.Sql.Engine do
  @moduledoc """
  What each relational database has to answer for the SQL nodes to work on it.

  A new engine is a module with these callbacks and an entry in
  `HeddleNodes.Services.Sql`, and every SQL node works on it.
  """

  @type result :: %{
          required(:columns) => [String.t()],
          required(:rows) => [list()],
          required(:count) => non_neg_integer(),
          optional(:last_id) => term()
        }

  @doc "Opens a pool of connections, linked to the caller."
  @callback connect(values :: map()) :: {:ok, pid()} | {:error, String.t()}

  @doc "Runs one statement."
  @callback query(conn :: term(), sql :: String.t(), params :: list()) ::
              {:ok, result()} | {:error, String.t()}

  @doc "Calls `fun` inside a transaction, and rolls it back when `fun` returns an error."
  @callback transaction(conn :: term(), fun :: (term() -> {:ok, term()} | {:error, String.t()})) ::
              {:ok, term()} | {:error, String.t()}

  @doc "How the dialect writes the parameter at a position."
  @callback placeholder(position :: pos_integer()) :: String.t()

  @doc "Quotes one name, like a column."
  @callback quote_name(name :: String.t()) :: String.t()

  @doc "The quotes that open a string in this dialect."
  @callback strings() :: [char()]

  @doc "Adds a limit and an offset to a SELECT, which can be nil."
  @callback paginate(
              sql :: String.t(),
              order_by? :: boolean(),
              limit :: integer(),
              offset :: integer()
            ) ::
              String.t()

  @doc "Writes an INSERT of `rows`, each a list of placeholders, that returns what it can."
  @callback insert(table :: String.t(), columns :: [String.t()], rows :: [[String.t()]]) ::
              String.t()

  @doc "Writes an INSERT that updates the row when `keys` already exist."
  @callback upsert(
              table :: String.t(),
              columns :: [String.t()],
              rows :: [[String.t()]],
              keys :: [String.t()]
            ) :: String.t()

  @doc "A query that returns the tables, in a `name` column."
  @callback tables() :: {String.t(), list()}

  @doc "A query that returns the columns of a table: `name`, `type`, `nullable`, `default`."
  @callback columns(table :: String.t()) :: {String.t(), list()}
end
