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
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:heddle_core, in_umbrella: true, only: :test},
      {:heddle_runtime, in_umbrella: true},
      {:fusion_kit, "~> 0.2.0"},
      {:req, "~> 0.5"},
      {:jason, "~> 1.2"}
    ]
  end
end
