# The pipe operator `|>` takes the value on its left
# and passes it as the *first argument* of the call on
# its right.
#
# Nested calls read inside-out, and every extra
# argument ends up far from the function it belongs
# to. Which call do `~r/\s+/` and `"-"` go to?
# (`~r/.../` is a regular expression; `\s+` matches
# runs of whitespace.)
title = "  Hello Pipe World  "
IO.inspect(String.replace(String.trim(String.downcase(title)), ~r/\s+/, "-"))

# Piped, the steps read top to bottom in the order
# they happen, and each line holds one function with
# its own arguments.
title
|> String.downcase()
|> String.trim()
|> String.replace(~r/\s+/, "-")
|> IO.inspect()

# The other way out is a variable per step. It reads
# in order too, but the names are noise when each
# step only feeds the next one.
lower = String.downcase(title)
trimmed = String.trim(lower)
slug = String.replace(trimmed, ~r/\s+/, "-")
IO.inspect(slug)

# Pipelines are also easy to change: adding or
# removing a step is one line. In nested code you edit
# both ends and recount parentheses. A typical data
# pipeline:
orders = [
  %{id: 1, total: 120, status: :paid},
  %{id: 2, total: 80, status: :refunded},
  %{id: 3, total: 300, status: :paid},
  %{id: 4, total: 45, status: :paid}
]

orders
|> Enum.filter(&(&1.status == :paid))
|> Enum.sort_by(& &1.total, :desc)
|> Enum.take(2)
|> Enum.map(& &1.id)
|> IO.inspect(label: "top paid orders")

# Pipes work because the standard library puts the
# "subject" (the string, the list, the map) first.
# Follow the same rule and your own small functions
# plug into pipelines the way built-ins do.
defmodule Slug do
  def normalize(text), do: text |> String.downcase() |> String.trim()
  def strip_punctuation(text), do: String.replace(text, ~r/[^\w\s-]/u, "")
  def hyphenate(text, separator \\ "-"), do: String.replace(text, ~r/\s+/, separator)

  def slugify(text) do
    text
    |> normalize()
    |> strip_punctuation()
    |> hyphenate()
  end
end

IO.puts(Slug.slugify("  Hello, Pipe World!  "))

# Small steps recombine. The same pieces build a
# different pipeline, here with `_` as the separator.
"Pattern Matching & Guards"
|> Slug.normalize()
|> Slug.strip_punctuation()
|> Slug.hyphenate("_")
|> IO.puts()

# `then/2` pipes into a position other than the first,
# and `tap/2` runs a side effect and passes the value
# through unchanged. Operators are functions in the
# `Kernel` module, so `Kernel.*(10)` multiplies the
# piped value by 10.
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
amount = 42

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
# > Credo (a popular linter) flags it for that
# > reason.
