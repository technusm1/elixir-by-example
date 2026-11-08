defmodule Greeter.MixProject do
  use Mix.Project

  def project do
    [app: :greeter, version: "0.1.0", elixir: "~> 1.20", deps: []]
  end

  def application do
    [mod: {Greeter.Application, []}]
  end
end
