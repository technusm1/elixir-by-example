defmodule KV.MixProject do
  use Mix.Project

  def project do
    [app: :kv, version: "0.1.0", elixir: "~> 1.20", deps: deps()]
  end

  def application do
    [mod: {KV.Application, []}]
  end

  defp deps do
    [{:libcluster, "~> 3.4"}]
  end
end
