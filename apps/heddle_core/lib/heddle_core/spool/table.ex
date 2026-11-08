defmodule HeddleCore.Spool.Table do
  @moduledoc """
  A table of Spool, in one workspace. See `HeddleCore.Spool`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias HeddleCore.Spool.Column

  @max_name 80

  schema "spool_tables" do
    field :name, :string
    field :columns, {:array, :map}, default: []
    field :workspace_id, :id

    # How many rows it has, when the query asks for it.
    field :row_count, :integer, virtual: true

    timestamps(type: :utc_datetime)
  end

  @doc """
  A changeset for the name and the columns. The workspace is set by the context.
  """
  def changeset(table, attrs) do
    table
    |> cast(attrs, [:name])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name])
    |> validate_length(:name, max: @max_name)
    |> put_columns(attrs)
    |> unique_constraint(:name,
      name: :spool_tables_workspace_id_name_index,
      message: "is already the name of a table"
    )
  end

  defp put_columns(changeset, attrs) do
    case attrs["columns"] || attrs[:columns] do
      nil ->
        changeset

      columns ->
        case Column.normalize(columns) do
          {:ok, columns} -> put_change(changeset, :columns, columns)
          {:error, message} -> add_error(changeset, :columns, message)
        end
    end
  end
end
