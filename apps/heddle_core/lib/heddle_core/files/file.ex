defmodule HeddleCore.Files.File do
  @moduledoc "A file a node kept during a run, see `HeddleCore.Files`."

  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}
  schema "run_files" do
    field :name, :string
    field :mime, :string
    field :size, :integer
    field :content, :binary

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
