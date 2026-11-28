defmodule HeddleNodes.Official do
  @moduledoc """
  The integrations Heddle maintains, all in heddlehq/integrations.

    * Packages need a driver or code. They enter Heddle when it's built, see
      `HeddleNodes.Packages` and `HEDDLE_INTEGRATIONS` in `apps/heddle_nodes/mix.exs`.
    * Manifests are downloaded from the catalog when a workspace installs them, like a
      community integration. The one whose YAML has the hash pinned here is official:
      it shows no "Not verified" warning, and no other manifest can take its id.
  """

  @packages ~w(cassandra dynamodb elasticsearch email ftp google_sheets jido mongodb neo4j redis s3 slack sql)

  # Raise a pin to move every instance to a new version of an official manifest.
  @manifests %{
    "notion" => %{
      version: "1.0.0",
      sha256: "1b9f2b07125437b543d1ede37ff7fbbc23e50751f9800865505c60cc3de85116"
    }
  }

  @doc "The ids of the official packages."
  def packages, do: @packages

  @doc "The pinned official manifests, by id."
  def manifests, do: @manifests

  @doc "The ids no community integration can take."
  def ids, do: @packages ++ Map.keys(@manifests)

  @doc "Whether `yaml` is the pinned version of the official manifest `id`."
  def manifest?(id, yaml) when is_binary(yaml) do
    case @manifests[id] do
      %{sha256: sha} -> sha == :crypto.hash(:sha256, yaml) |> Base.encode16(case: :lower)
      nil -> false
    end
  end

  def manifest?(_id, _yaml), do: false
end
