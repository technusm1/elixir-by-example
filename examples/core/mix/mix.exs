defmodule Bill.MixProject do
  use Mix.Project

  def project do
    [
      app: :bill,
      version: "0.1.0",
      elixir: "~> 1.20",
      elixirc_options: [warnings_as_errors: true],
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [{:decimal, "~> 3.2"}]
  end
end
