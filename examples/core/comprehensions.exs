# A comprehension (`for`) maps, filters and combines
# enumerables in one expression. It returns a list by
# default.
squares = for n <- 1..5, do: n * n
IO.inspect(squares, label: "squares")

# Extra clauses after the generator are *filters*.
evens = for n <- 1..10, rem(n, 2) == 0, do: n
IO.inspect(evens, label: "evens")

# Several generators give every combination, like
# nested loops.
pairs = for x <- [:a, :b], y <- [1, 2], do: {x, y}
IO.inspect(pairs, label: "pairs")

# The left side of `<-` is a pattern. Elements that
# don't match are skipped silently, which makes
# comprehensions handy for picking out results.
results = [{:ok, 1}, {:error, :timeout}, {:ok, 3}]
oks = for {:ok, value} <- results, do: value
IO.inspect(oks, label: "oks")

# Maps enumerate as `{key, value}` tuples.
stock = %{apple: 0, pear: 4, fig: 2}
in_stock = for {fruit, n} <- stock, n > 0, do: fruit
IO.inspect(Enum.sort(in_stock), label: "in stock")

# `into:` collects into something other than a list,
# such as a map or a string.
upcased = for {k, v} <- %{a: "x", b: "y"}, into: %{}, do: {k, String.upcase(v)}
IO.inspect(upcased, label: "into map")

# Bitstring generators walk binaries byte by byte.
bytes = for <<b <- "hi!">>, do: b
IO.inspect(bytes, label: "bytes")

# `uniq: true` drops duplicates, and `reduce:` turns a
# comprehension into a fold with an accumulator.
IO.inspect(for(x <- [1, 1, 2, 3, 3], uniq: true, do: x * 10), label: "uniq")

total =
  for n <- 1..4, reduce: 0 do
    acc -> acc + n
  end

IO.inspect(total, label: "reduce")

# > **Pitfall:** a comprehension doesn't update outer
# > variables. Writing `count = 0` and then
# > `for x <- list do count = count + 1 end` leaves
# > `count` at 0 (the compiler warns that the inner
# > variable is unused). Use `reduce:` or
# > `Enum.reduce/3` to carry state.
#
# > **Pitfall:** the silent skip on pattern mismatch
# > can hide bugs: `for {:ok, v} <- results` drops
# > errors without a trace. Match errors explicitly
# > when you need to know about them.
