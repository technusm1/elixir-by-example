defmodule Orders.MixProject do
  use Mix.Project

  def project do
    [app: :orders, version: "0.1.0", elixir: "~> 1.20", deps: []]
  end

  def application do
    # :ssh ships with Erlang/OTP; the release must include it.
    [mod: {Orders.Application, []}, extra_applications: [:logger, :ssh]]
  end
end
