defmodule Span.CLI do
  @moduledoc "Adds up durations given on the command line."

  require Logger

  @doc "Prints the sum of the durations in `args`; logs and skips bad ones."
  @spec main([String.t()]) :: :ok
  def main(args) do
    total =
      Enum.reduce(args, 0, fn arg, total ->
        case Span.parse(arg) do
          {:ok, seconds} ->
            total + seconds

          {:error, reason} ->
            Logger.warning("skipping #{inspect(arg)}: #{inspect(reason)}")
            total
        end
      end)

    IO.puts("total: " <> Span.format(total))
  end
end
