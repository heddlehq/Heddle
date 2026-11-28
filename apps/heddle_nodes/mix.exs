defmodule HeddleNodes.MixProject do
  use Mix.Project

  @version File.read!(Path.expand("../../VERSION", __DIR__)) |> String.trim()

  def project do
    [
      app: :heddle_nodes,
      version: @version,

      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      test_coverage: [summary: [threshold: 0]],
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :ftp, :public_key],
      mod: {HeddleNodes.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:heddle, in_umbrella: true},
      {:heddle_core, in_umbrella: true, only: :test},
      {:heddle_runtime, in_umbrella: true},
      bobbin(),
      {:nimble_csv, "~> 1.3"},
      {:req, "~> 0.5"},
      {:jason, "~> 1.2"}
    ] ++ integrations()
  end

  # BOBBIN_PATH points at a Bobbin checkout, to try a change in both at once.
  defp bobbin do
    case System.get_env("BOBBIN_PATH") do
      nil -> {:bobbin, "~> 0.6"}
      path -> {:bobbin, path: Path.expand(path), override: true}
    end
  end

  # The official integrations in code (see HeddleNodes.Official) this build carries,
  # from heddlehq/integrations: HEDDLE_INTEGRATIONS=all, or a list like "sql,email".
  # None by default in prod, every one in dev and test. HEDDLE_INTEGRATIONS_PATH points
  # at a checkout of that repo, to change both at once.
  @official ~w(cassandra dynamodb elasticsearch email ftp google_sheets mongodb neo4j redis s3 slack sql)

  defp integrations do
    ids =
      case System.get_env("HEDDLE_INTEGRATIONS") do
        nil -> if Mix.env() == :prod, do: [], else: @official
        "all" -> @official
        list -> list |> String.split(",", trim: true) |> Enum.map(&String.trim/1)
      end

    Enum.map(ids, &integration/1)
  end

  defp integration(id) do
    app = String.to_atom("heddle_#{id}")

    case System.get_env("HEDDLE_INTEGRATIONS_PATH") do
      nil ->
        {app,
         git: "https://github.com/heddlehq/integrations.git",
         sparse: "integrations/#{id}",
         branch: "main"}

      path ->
        {app, path: Path.join(Path.expand(path), "integrations/#{id}")}
    end
  end
end
