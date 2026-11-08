defmodule HeddleNodes.Docs do
  @moduledoc """
  The reference of every node, as the documentation site shows it.

  What a node is comes from its definition: its name, what it does, its fields, its
  inputs and its outputs. What it leaves in the run comes from `docs/nodes/`, one JSON
  file per category, which holds for each node:

    * `"result"`, an example of what the node leaves in `result`, or `null` when it
      leaves `result` alone;
    * `"notes"`, with `"en"` and `"pt"`, what else is worth knowing, in Markdown.

  `mix heddle.docs` writes it all to `docs/reference/nodes.json`, which the site reads.
  A test fails when a node has no entry, or when the file is out of date.
  """

  alias HeddleNodes.Nodes

  @categories [
    :trigger,
    :flow_control,
    :data_manipulation,
    :code,
    :http,
    :ai,
    :database,
    :email,
    :slack,
    :google_sheets,
    :s3,
    :ftp,
    :utility
  ]

  @doc "The root of the repository, where `docs/` is."
  def root, do: Path.expand("../../../..", __DIR__)

  @doc "Where `mix heddle.docs` writes the reference."
  def reference_path(root \\ root()), do: Path.join(root, "docs/reference/nodes.json")

  @doc "The reference, as the JSON the site reads."
  def encode(root \\ root()) do
    root |> reference() |> Jason.encode!(pretty: true) |> Kernel.<>("\n")
  end

  @doc "The categories and their nodes, in the order the site lists them."
  def reference(root \\ root()) do
    notes = notes(root)
    by_category = Enum.group_by(Nodes.all_nodes(), & &1.category)

    categories =
      for category <- @categories ++ ((Map.keys(by_category) -- @categories) |> Enum.sort()),
          nodes = Map.get(by_category, category, []),
          nodes != [] do
        %{
          "id" => to_string(category),
          "label" => Nodes.category_label(category),
          "nodes" => Enum.map(nodes, &node(&1, notes))
        }
      end

    %{"categories" => categories}
  end

  @doc """
  The entries of `docs/nodes/`, by node name. Raises when one is malformed.
  """
  def notes(root \\ root()) do
    root
    |> Path.join("docs/nodes/*.json")
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.reduce(%{}, fn file, acc ->
      file |> File.read!() |> Jason.decode!() |> Map.merge(acc)
    end)
  end

  @doc "The names of the nodes `docs/nodes/` doesn't cover, and of entries for no node."
  def coverage(root \\ root()) do
    names = Enum.map(Nodes.all_nodes(), & &1.name)
    documented = root |> notes() |> Map.keys()

    %{missing: names -- documented, unknown: documented -- names}
  end

  @doc "The address of a node's page: `Slack: Send Message` is `slack-send-message`."
  def slug(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  defp node(definition, notes) do
    entry = Map.get(notes, definition.name, %{})

    %{
      "name" => definition.name,
      "slug" => slug(definition.name),
      "description" => definition.description,
      "icon" => definition.icon,
      "group" => definition[:group],
      "inputs" => Enum.map(definition.inputs || [], &to_string/1),
      "outputs" => Enum.map(definition.outputs || [], &to_string/1),
      "credential" => credential(definition),
      "fields" =>
        definition.ui_fields |> Enum.reject(&(&1.type == :credential)) |> Enum.map(&field/1),
      "result" => Map.get(entry, "result"),
      "notes" => Map.get(entry, "notes", %{})
    }
  end

  defp credential(definition) do
    Enum.find_value(definition.ui_fields, fn
      %{type: :credential, kind: kind} -> kind
      _field -> nil
    end)
  end

  defp field(field) do
    %{
      "name" => to_string(field.name),
      "label" => field.label,
      "type" => to_string(field.type),
      "default" => field[:default],
      "options" => options(field[:options]),
      "capability" => field[:capability] && to_string(field[:capability])
    }
    |> Map.reject(fn {_key, value} -> value in [nil, []] end)
  end

  defp options(nil), do: nil

  defp options(options) do
    Enum.map(options, fn
      %{value: value, label: label} -> %{"value" => to_string(value), "label" => label}
      value -> %{"value" => to_string(value), "label" => to_string(value)}
    end)
  end
end
