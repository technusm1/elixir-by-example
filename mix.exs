defmodule Ebe.MixProject do
  use Mix.Project

  def project do
    [
      app: :ebe,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: false,
      elixirc_options: [warnings_as_errors: true],
      deps: deps(),
      aliases: aliases(),
      dialyzer: [
        plt_local_path: "_build/plts",
        plt_add_apps: [:mix],
        flags: [:error_handling, :extra_return, :missing_return, :underspecs]
      ]
    ]
  end

  def cli do
    [preferred_envs: [check: :test]]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:mdex, "~> 0.14"},
      {:makeup, "~> 1.2"},
      {:makeup_elixir, "~> 1.0"},
      {:phoenix_live_view, "~> 1.2"},
      {:bandit, "~> 1.8"},
      {:file_system, "~> 1.1"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      check: [
        "format --check-formatted",
        "compile --warnings-as-errors --force",
        "credo --strict",
        "dialyzer",
        "test",
        "ebe.build"
      ]
    ]
  end
end
