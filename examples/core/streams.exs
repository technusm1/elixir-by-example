# `Stream` functions look like `Enum` functions but
# are *lazy*: they build a recipe instead of a result.
# Nothing runs until an `Enum` function consumes it.
lazy = Stream.map([1, 2, 3], &(&1 * 2))
IO.inspect(is_struct(lazy, Stream), label: "a %Stream{}, not a list")
IO.inspect(Enum.to_list(lazy), label: "materialized")

# Laziness changes the *order* of work. Enum finishes
# each step for every element; Stream pushes each
# element through every step before the next one.
IO.puts("-- Enum:")

[1, 2]
|> Enum.map(&IO.inspect(&1, label: "map"))
|> Enum.each(&IO.inspect(&1, label: "each"))

IO.puts("-- Stream:")

[1, 2]
|> Stream.map(&IO.inspect(&1, label: "map"))
|> Enum.each(&IO.inspect(&1, label: "each"))

# Because only what's needed is computed, streams can
# be infinite. `Stream.iterate/2` and
# `Stream.cycle/1` never end on their own; `take/2`
# stops them.
powers = Stream.iterate(1, &(&1 * 2)) |> Enum.take(10)
IO.inspect(powers, label: "powers of 2")

IO.inspect(Stream.cycle([:red, :green]) |> Enum.take(5), label: "cycle")

# A large range costs nothing until consumed, and only
# the first few matches are ever computed here.
first =
  1..10_000_000
  |> Stream.filter(&(rem(&1, 7) == 0))
  |> Stream.map(&(&1 * &1))
  |> Enum.take(3)

IO.inspect(first, label: "first 3")

# `Stream.unfold/2` generates values from state, a
# neat way to express sequences like Fibonacci.
fib = Stream.unfold({0, 1}, fn {a, b} -> {a, {b, a + b}} end)
IO.inspect(Enum.take(fib, 10), label: "fib")

# Streams shine with resources read piece by piece:
# `File.stream!/1` reads a file line by line, and
# `Stream.chunk_every/2` batches work.
batches = ~w(a b c d e f g) |> Stream.chunk_every(3) |> Enum.to_list()
IO.inspect(batches, label: "batches")

# > **Pitfall:** a stream that is never consumed does
# > nothing. `Stream.each(list, &IO.puts/1)` on its own
# > prints nothing; end the pipeline with `Enum.each/2`,
# > `Enum.to_list/1` or `Stream.run/1`.
#
# > **Pitfall:** streams aren't free. For small lists,
# > each lazy step adds overhead, and plain `Enum` is
# > usually faster. Reach for `Stream` when inputs are
# > big, infinite, or come from I/O.
