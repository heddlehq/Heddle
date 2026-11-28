defmodule HeddleCore.Files do
  @moduledoc """
  The files nodes pass between them: a node that downloads one keeps it here and
  passes on a reference, `%{"file" => %{"id", "name", "mime", "size"}}`, and a node
  that uploads one reads it back, so files don't travel inside a run's data. Nodes
  reach this through `HeddleNodes.Files`, which Bobbin uses (see `Bobbin.Files`).

  Files live in the database, which the UI and the workers share, and are deleted
  `retention_days` after they were kept (7 by default, `:heddle_core, :files`), by
  `HeddleWorker.FilePruneWorker`. A file larger than `max_bytes` (50 MB) is refused.
  """

  import Ecto.Query

  alias HeddleCore.Files.File, as: RunFile
  alias HeddleCore.Repo

  @doc "Keeps `content` with its `name` and `mime`, and returns its reference."
  def store(content, meta) do
    content = IO.iodata_to_binary(content)
    size = byte_size(content)

    if size > max_bytes() do
      {:error,
       "The file is #{div(size, 1_000_000)} MB, more than the #{div(max_bytes(), 1_000_000)} MB a run may keep."}
    else
      file = %RunFile{
        id: Base.encode16(:crypto.strong_rand_bytes(16), case: :lower),
        name: meta["name"] || "file",
        mime: meta["mime"] || "application/octet-stream",
        size: size,
        content: content
      }

      case Repo.insert(file) do
        {:ok, file} ->
          {:ok, %{"id" => file.id, "name" => file.name, "mime" => file.mime, "size" => file.size}}

        {:error, _changeset} ->
          {:error, "Could not keep the file."}
      end
    end
  end

  @doc "The content of the file a reference points at."
  def read(%{"id" => id}) when is_binary(id) do
    case Repo.one(from f in RunFile, where: f.id == ^id, select: f.content) do
      nil -> {:error, "The file is gone: files are kept #{retention_days()} days."}
      content -> {:ok, content}
    end
  end

  def read(_ref), do: {:error, "That isn't a file."}

  @doc "Deletes the files older than the retention, and returns how many."
  def prune(now \\ DateTime.utc_now()) do
    cutoff = DateTime.add(now, -retention_days() * 86_400, :second)
    {count, _} = Repo.delete_all(from f in RunFile, where: f.inserted_at < ^cutoff)
    count
  end

  defp retention_days, do: config()[:retention_days] || 7
  defp max_bytes, do: config()[:max_bytes] || 50_000_000
  defp config, do: Application.get_env(:heddle_core, :files, [])
end
