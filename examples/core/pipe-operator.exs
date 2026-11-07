# The pipe operator `|>` takes the value on its left
# and passes it as the *first argument* of the call on
# its right. Nested calls read inside-out:
IO.inspect(Enum.sum(Enum.map(String.split("1 2 3"), &String.to_integer/1)))

# The same thing, piped, reads top to bottom in the
# order things happen.
"1 2 3"
|> String.split()
|> Enum.map(&String.to_integer/1)
|> Enum.sum()
|> IO.inspect()

# This works because the standard library puts the
# "subject" (the string, the list, the map) first.
# Follow the same rule in your own functions.
defmodule Text do
  def shout(text, suffix \\ "!"), do: String.upcase(text) <> suffix
end

"hello" |> Text.shout() |> IO.puts()
"hello" |> Text.shout("?!") |> IO.puts()

# `then/2` pipes into a position other than the first,
# and `tap/2` runs a side effect and passes the value
# through unchanged.
5
|> then(&Integer.pow(2, &1))
|> tap(&IO.puts("2^5 is #{&1}"))
|> Kernel.*(10)
|> IO.inspect(label: "times ten")

# `IO.inspect/2` returns its argument, so you can
# sprinkle it into a pipeline to see each step.
[3, 1, 2]
|> IO.inspect(label: "input")
|> Enum.sort()
|> IO.inspect(label: "sorted")
|> Enum.reverse()
|> IO.inspect(label: "reversed")

# > **Pitfall:** `|>` binds *looser* than arithmetic
# > and concatenation. `1 + 2 |> f()` really is
# > `f(3)`, but `"total: " <> amount |> to_string()`
# > is `("total: " <> amount) |> to_string()`, which
# > crashes when `amount` is an integer. Many guides
# > (and agents) get this backwards.
amount = Enum.random([42])

try do
  ("total: " <> amount) |> Integer.to_string() |> IO.puts()
rescue
  e in ArgumentError -> IO.puts("ArgumentError: " <> Exception.message(e))
end

# > Parenthesize what you mean, or move the pipe so
# > the conversion happens first.
IO.puts("total: " <> (amount |> Integer.to_string()))

# > **Pitfall:** piping into an anonymous function
# > needs the dot, `|> f.()`. And a single-step pipe
# > (`foo |> bar()`) is usually clearer as `bar(foo)`;
# > Credo flags it for that reason.
