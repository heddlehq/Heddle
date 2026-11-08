defmodule HeddleCore.Executions.Execution do
  use Ecto.Schema
  import Ecto.Changeset

  alias HeddleCore.Flows.Flow
  alias HeddleCore.Flows.Version

  @primary_key {:id, :binary_id, autogenerate: true}
  @statuses ~w(queued running waiting succeeded failed)

  schema "executions" do
    field :public_id, :string
    field :status, :string, default: "queued"
    field :input, :map, default: %{}
    field :result, :map
    field :error, :map
    field :logs, {:array, :map}, default: []
    field :response, :map
    # What is left of a run a Wait paused. See `HeddleNodes.Runner`.
    field :paused, :map
    # The secret part of the address that resumes a Wait on a call.
    field :resume_token, :string, redact: true
    field :started_at, :utc_datetime
    field :finished_at, :utc_datetime

    belongs_to :flow, Flow
    # The graph this run runs, which the flow may have changed since.
    belongs_to :flow_version, Version

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  @doc false
  def changeset(execution, attrs) do
    execution
    |> cast(attrs, [
      :public_id,
      :flow_id,
      :flow_version_id,
      :status,
      :input,
      :result,
      :error,
      :logs,
      :started_at,
      :finished_at
    ])
    |> validate_required([:public_id, :flow_id, :status, :input, :logs])
    |> validate_format(:public_id, ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/)
    |> validate_inclusion(:status, @statuses)
    |> assoc_constraint(:flow)
    |> assoc_constraint(:flow_version)
    |> check_constraint(:status, name: :executions_status_check)
    |> unique_constraint(:public_id)
    |> unique_constraint(:resume_token)
  end
end
