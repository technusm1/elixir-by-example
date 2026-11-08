defmodule Tally.MixProject do
  use Mix.Project

  def project do
    [app: :tally, version: "0.1.0", elixir: "~> 1.20", deps: []]
  end

  def application do
    [
      mod: {Tally.Application, []},
      extra_applications: [:logger]
    ]
  end
end
