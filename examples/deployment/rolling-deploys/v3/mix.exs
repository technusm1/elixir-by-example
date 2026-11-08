defmodule Tally.MixProject do
  use Mix.Project

  def project do
    [app: :tally, version: "3.0.0", elixir: "~> 1.20", deps: []]
  end

  def application do
    [mod: {Tally.Application, []}]
  end
end
