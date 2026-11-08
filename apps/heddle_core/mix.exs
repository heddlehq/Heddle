defmodule HeddleCore.MixProject do
  use Mix.Project

  @version File.read!(Path.expand("../../VERSION", __DIR__)) |> String.trim()

  def project do
    [
      app: :heddle_core,
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
      mod: {HeddleCore.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:heddle, in_umbrella: true},
      {:pbkdf2_elixir, "~> 2.0"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:jason, "~> 1.2"},
      {:oban, "~> 2.0"},
      {:req, "~> 0.5"},
      {:phoenix_pubsub, "~> 2.1"},
      # One editing session per flow across the cluster, see `HeddleCore.Flows.Session`.
      {:horde, "~> 0.9"}
    ]
  end
end
