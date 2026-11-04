defmodule Heddle.Umbrella.MixProject do
  use Mix.Project

  @version File.read!("VERSION") |> String.trim()

  def project do
    [
      apps_path: "apps",
      version: @version,
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      releases: releases(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  defp deps do
    []
  end

  defp releases do
    [
      heddle_ui: [
        applications: [
          heddle_core: :permanent,
          heddle_runtime: :permanent,
          heddle_nodes: :permanent,
          heddle_ai: :permanent,
          heddle_ui: :permanent
        ]
      ],
      heddle_worker: [
        applications: [
          heddle_core: :permanent,
          heddle_runtime: :permanent,
          heddle_nodes: :permanent,
          heddle_ai: :permanent,
          heddle_worker: :permanent
        ]
      ]
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": [
        "ecto.create",
        "ecto.migrate",
        "run apps/heddle_core/priv/repo/seeds.exs"
      ],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": [
        &install_ui_assets/1,
        "tailwind.install --if-missing",
        "esbuild.install --if-missing"
      ],
      "assets.build": ["compile", "tailwind heddle_ui", "esbuild heddle_ui"],
      "assets.deploy": [
        "tailwind heddle_ui --minify",
        "esbuild heddle_ui --minify",
        "phx.digest -o apps/heddle_ui/priv/static"
      ],
      precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"]
    ]
  end

  defp install_ui_assets(_args) do
    assets_path = Path.expand("apps/heddle_ui/assets", File.cwd!())

    cond do
      executable = System.find_executable("npm") ->
        run_installer(executable, ["install"], assets_path, "npm")

      executable = System.find_executable("bun") ->
        run_installer(executable, ["install"], assets_path, "bun")

      true ->
        Mix.raise("""
        Could not install UI asset dependencies.

        Neither `npm` nor `bun` was found in PATH.
        Install one of them and run `mix setup` again.
        """)
    end
  end

  defp run_installer(executable, args, assets_path, label) do
    Mix.shell().info("Installing UI asset dependencies with #{label} in #{assets_path}")

    case System.cmd(executable, args,
           cd: assets_path,
           into: IO.stream(:stdio, :line),
           stderr_to_stdout: true
         ) do
      {_output, 0} ->
        :ok

      {_output, status} ->
        Mix.raise("#{label} install failed in #{assets_path} with exit status #{status}")
    end
  end
end
