defmodule Quota.MixProject do
  use Mix.Project

  def project do
    [
      app: :quota,
      version: "0.1.0",
      elixir: "~> 1.20",
      elixirc_options: [warnings_as_errors: true],
      deps: []
    ]
  end

  def application do
    [
      mod: {Quota.Application, []},
      extra_applications: [:logger]
    ]
  end
end
