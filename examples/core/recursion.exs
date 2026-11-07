# Elixir has no `for`/`while` loops that mutate a
# counter. Repetition is recursion: a function that
# calls itself on a smaller problem, with one clause
# for the base case.
defmodule MyList do
  def sum([]), do: 0
  def sum([head | tail]), do: head + sum(tail)
end

IO.inspect(MyList.sum([1, 2, 3, 4]), label: "sum")

# Pattern matching on `[head | tail]` and `[]` picks
# the clause. The base case comes first so it's
# obvious when recursion stops.
defmodule Countdown do
  def run(0), do: IO.puts("liftoff!")

  def run(n) when n > 0 do
    IO.puts(n)
    run(n - 1)
  end
end

Countdown.run(3)

# A *tail call* is one where the recursive call is the
# very last thing the function does. The BEAM reuses
# the stack frame, so it runs in constant stack space.
# The usual trick is an accumulator argument.
defmodule Fact do
  def of(n), do: of(n, 1)

  defp of(0, acc), do: acc
  defp of(n, acc) when n > 0, do: of(n - 1, acc * n)
end

IO.inspect(Fact.of(20), label: "20!")

# Integers are arbitrary precision, so this doesn't
# overflow; it just gets big.
IO.inspect(Fact.of(30), label: "30!")

# Building a list? Prepend while recursing (cheap) and
# reverse once at the end (one pass).
defmodule Doubler do
  def double(list), do: double(list, [])

  defp double([], acc), do: Enum.reverse(acc)
  defp double([h | t], acc), do: double(t, [h * 2 | acc])
end

IO.inspect(Doubler.double([1, 2, 3]), label: "doubled")

# In everyday code you rarely write this by hand:
# `Enum` and `Stream` already implement these loops.
IO.inspect(Enum.sum([1, 2, 3, 4]), label: "Enum.sum")

# > **Pitfall:** "always make it tail-recursive" is a
# > myth carried over from older advice. Since OTP R12,
# > body recursion like `MyList.sum/1` is often just as
# > fast, and for building lists it can beat the
# > accumulator-plus-`Enum.reverse/1` version. Tail
# > recursion matters for *infinite* loops, like a
# > process's receive loop, which must never grow the
# > stack.
#
# > **Pitfall:** forgetting the base case, or a guard
# > like `when n > 0`, gives you an infinite loop or a
# > `FunctionClauseError` on input you didn't expect
# > (`Countdown.run(-1)`). Guard against bad input at
# > the edge.
