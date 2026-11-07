defmodule Mix.Tasks.Ebe.Runner do
  @shortdoc "Builds the in-browser Elixir runtime (Popcorn) into runner/out"
  @moduledoc """
  Cooks the `runner/` Mix project with Popcorn. `mix ebe.build` copies the
  result to `dist/popcorn/`. Only needed when the toolchain, Popcorn, or
  `runner/` changes.

      mix ebe.runner
  """

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    runner = Path.expand("../../../runner", __DIR__)
    env = [{"MIX_ENV", "prod"}]

    for args <- [["deps.get"], ["popcorn.cook", "--out-dir", "out"]] do
      {_, status} =
        System.cmd("mix", args, cd: runner, env: env, into: IO.stream(), stderr_to_stdout: true)

      if status != 0, do: Mix.raise("`mix #{Enum.join(args, " ")}` failed in runner/")
    end

    :ok
  end
end
