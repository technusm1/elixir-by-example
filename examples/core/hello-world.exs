# Our first program prints the classic message.
# Save it as `hello-world.exs` and run it with
# `elixir hello-world.exs`. No project or compile
# step needed: `.exs` files are scripts.
IO.puts("Hello, world!")

# `IO.puts/1` writes a string followed by a newline.
# The `/1` is the function's *arity*, its number of
# arguments. In Elixir, `puts/1` and `puts/2` are
# different functions.
IO.puts(:stderr, "this goes to standard error")

# `IO.inspect/2` prints any value in its Elixir form
# and *returns it unchanged*, so you can drop it into
# the middle of an expression to debug it.
[1, 2, 3] |> IO.inspect(label: "list") |> Enum.sum() |> IO.inspect(label: "sum")

# > **Pitfall:** `IO.puts/1` wants something printable
# > as text (a string, atom, number, or charlist). For
# > maps, lists of structs and the like, use
# > `IO.inspect/2`; `IO.puts(%{a: 1})` raises
# > `Protocol.UndefinedError`.
