defmodule Span.MixProject do
  use Mix.Project

  def project do
    [
      app: :span,
      version: "0.1.0",
      elixir: "~> 1.20",
      elixirc_options: [warnings_as_errors: true],
      deps: []
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end
end
