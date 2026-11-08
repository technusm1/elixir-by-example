# Sigils are literals that start with `~`, a letter,
# and a pair of delimiters. They're shortcuts for
# common kinds of text and data.
#
# `~s` builds a string, handy when it contains
# double quotes.
IO.puts(~s(She said "hi"))

# `~w` splits on whitespace into a list of words.
# The `a` modifier makes atoms instead of strings.
IO.inspect(~w(red green blue))
IO.inspect(~w(red green blue)a)

# `~r` is a regular expression (PCRE). Modifiers like
# `i` (case-insensitive) go after the delimiter.
IO.inspect(String.match?("Elixir", ~r/elixir/i))
IO.inspect(Regex.run(~r/(\d+)-(\d+)/, "range: 10-20"))
IO.inspect(String.replace("a1b22c333", ~r/\d+/, "#"))

# Named captures come back as a map.
IO.inspect(Regex.named_captures(~r/(?<user>\w+)@(?<host>[\w.]+)/, "ada@example.com"))

# `~c` is a charlist, a list of integer codepoints.
# You mostly meet these when calling Erlang
# libraries.
IO.inspect(~c"abc")
IO.inspect(~c"abc" == [97, 98, 99])

# `~D` is a date, `~T` a time of day and `~U` a UTC
# date and time. They're checked at compile time, so
# an invalid date like `~D[2026-02-30]` won't
# compile.
date = ~D[2026-11-07]
IO.inspect(date)
IO.inspect(Date.add(date, 30))
IO.inspect(~T[09:30:00])
IO.inspect(~U[2026-11-07 09:30:00Z])

# Uppercase sigils don't interpolate or process
# escapes, which is nice for regexes and templates.
name = "Ada"
IO.puts(~s(hello #{name}\n) |> String.trim())
IO.puts(~S(hello #{name}\n))

# Any delimiter pair works, so pick one that doesn't
# clash with the content.
IO.puts(~s{paths like "/a/b" are easy})
IO.puts(~s|and (parens) too|)

# A custom sigil is a function named `sigil_x` (or a
# multi-letter uppercase name) that receives the
# content and the modifiers. `import` the module to
# use it. (In a script, the importing code must live
# in a separate module from the definition.) `?n` is
# the integer codepoint of the character `n`.
defmodule Sigils do
  def sigil_i(text, []), do: String.to_integer(text)
  def sigil_i(text, [?n]), do: -String.to_integer(text)
end

defmodule Demo do
  import Sigils

  def run do
    IO.inspect(~i(42))
    IO.inspect(~i(42)n)
  end
end

Demo.run()

# > **Pitfall:** `~w(...)a` creates atoms. Fine for
# > literals you write, but never build atom lists from
# > user input (atoms aren't garbage collected).
#
# > **Pitfall:** `'abc'` in single quotes is a
# > *charlist*, not a string, and `"abc" == ~c"abc"` is
# > `false`. Single-quoted charlists are deprecated in
# > modern Elixir (the compiler warns); older code and
# > some agents still write them. Use `~c"..."` when an
# > Erlang API wants a charlist, and `"..."` otherwise.
