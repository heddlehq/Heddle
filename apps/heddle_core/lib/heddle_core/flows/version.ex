defmodule HeddleCore.Flows.Version do
  @moduledoc """
  A graph a flow had, kept as it was. A version never changes.

  Its `kind` says why it was kept:

    * `"publish"`: someone published it, so it is or was what runs in production. One
      that puts an older version back in production has that version as `source`.
    * `"checkpoint"`: the draft as it was, kept on its own every so often and before it
      is replaced, so it can be brought back.
    * `"run"`: the draft as a run from the editor or the agent took it, so the run
      shows what it ran.

  `author` made it, and `contributor_ids` are the people who changed the draft since
  the version before. See `HeddleCore.Flows.Versions`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias HeddleCore.Accounts.User
  alias HeddleCore.Flows.Flow

  @kinds ~w(publish checkpoint run)

  schema "flow_versions" do
    field :number, :integer
    field :kind, :string
    field :nodes, {:array, :map}, default: []
    field :connections, {:array, :map}, default: []
    field :comments, {:array, :map}, default: []
    field :note, :string
    field :contributor_ids, {:array, :integer}, default: []

    belongs_to :flow, Flow
    belongs_to :author, User
    belongs_to :source, __MODULE__, foreign_key: :source_version_id

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def kinds, do: @kinds

  @doc false
  def changeset(version, attrs) do
    version
    |> cast(attrs, [:kind, :nodes, :connections, :comments, :note, :contributor_ids])
    |> validate_required([:kind])
    |> validate_inclusion(:kind, @kinds)
    |> validate_length(:note, max: 500)
    |> check_constraint(:kind, name: :flow_versions_kind_check)
    |> unique_constraint([:flow_id, :number])
  end
end
