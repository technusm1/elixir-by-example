defmodule EbeRunner.MixProject do
  use Mix.Project

  # The in-browser runtime for "Run" buttons. Cooked by Popcorn into runner/out,
  # which the site build copies to /popcorn. Kept separate from the generator so
  # none of the site tooling ends up in the WebAssembly bundle.
  def project do
    [
      app: :ebe_runner,
      version: "0.1.0",
      elixir: "~> 1.20",
      elixirc_options: [warnings_as_errors: true],
      deps: [{:popcorn, "~> 1.0"}]
    ]
  end

  def application do
    [extra_applications: [:logger], mod: {EbeRunner.Application, []}]
  end
end
