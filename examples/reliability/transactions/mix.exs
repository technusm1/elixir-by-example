defmodule Bank.MixProject do
  use Mix.Project

  def project do
    [app: :bank, version: "0.1.0", elixir: "~> 1.20", deps: deps()]
  end

  def application do
    [mod: {Bank.Application, []}]
  end

  defp deps do
    [{:ecto_sqlite3, "~> 0.26"}]
  end
end
