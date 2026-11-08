# `case` matches a value against patterns, top to
# bottom. Clauses can have guards: a `when` condition
# after the pattern that must also be true.
# `Enum.map/2` calls a function on each element of a
# list and collects the results.
classify = fn value ->
  case value do
    0 -> "zero"
    n when is_integer(n) and n < 0 -> "negative"
    n when is_integer(n) -> "positive"
    _ -> "not an integer"
  end
end

IO.inspect(Enum.map([0, -5, 7, :x], classify))

# No clause matching raises `CaseClauseError`.
try do
  case :maybe do
    :yes -> 1
    :no -> 2
  end
rescue
  e in CaseClauseError -> IO.puts(Exception.message(e))
end

# `cond` picks the first condition that's truthy.
# Useful when you test conditions, not shapes.
fizzbuzz = fn n ->
  cond do
    rem(n, 15) == 0 -> "FizzBuzz"
    rem(n, 3) == 0 -> "Fizz"
    rem(n, 5) == 0 -> "Buzz"
    true -> n
  end
end

IO.inspect(Enum.map(1..15, fizzbuzz))

# `if` and `unless` handle a single condition.
# Everything is an expression, so they return values.
# Without `else`, a false `if` returns `nil`.
temp = 31
label = if temp > 30, do: "hot", else: "fine"
IO.inspect(label)
IO.inspect(if false, do: :never)

# Variables bound inside `if`, `case` or `cond` don't
# leak out. Bind the result instead.
count = 0

count =
  if temp > 30 do
    count + 1
  else
    count
  end

IO.inspect(count)

# > **Pitfall:** rebinding inside a block doesn't change
# > the outer variable. `if x, do: count = count + 1`
# > leaves `count` unchanged afterwards (and Elixir
# > warns the inner variable is unused). Always write
# > `count = if ..., do: ..., else: ...`.
#
# > **Pitfall:** reaching for nested `if`s is usually a
# > sign you want `case` on a tuple, or multiple
# > function clauses. [Guards](/core/guards) puts the
# > two side by side.
