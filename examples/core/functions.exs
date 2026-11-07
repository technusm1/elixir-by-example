# Anonymous functions are values. Create them with
# `fn`, call them with a dot.
add = fn a, b -> a + b end
IO.inspect(add.(1, 2))

# The dot separates calling a variable holding a
# function from calling a named function.
IO.inspect(is_function(add))
IO.inspect(is_function(add, 2))

# A function can have several clauses, matched like
# `case`. All clauses must take the same number of
# arguments.
describe = fn
  [] -> "empty"
  [_] -> "one item"
  list when is_list(list) -> "#{length(list)} items"
end

IO.inspect(describe.([]))
IO.inspect(describe.([1, 2, 3]))

# Functions close over the variables around them. The
# value is captured at creation time.
greeting = "Hello"
greet = fn name -> "#{greeting}, #{name}!" end
greeting = "Bye"
IO.inspect(greet.("Ada"))
IO.inspect(greeting)

# The capture operator `&` turns a named function into
# a value. Name it with its arity.
upcase = &String.upcase/1
IO.inspect(upcase.("elixir"))
IO.inspect(Enum.map(["a", "b"], &String.upcase/1))

# `&` also builds short anonymous functions, with
# `&1`, `&2` as the arguments.
double = &(&1 * 2)
IO.inspect(Enum.map([1, 2, 3], double))
IO.inspect(Enum.reduce([1, 2, 3], 0, &(&1 + &2)))

# Functions that return functions.
multiplier = fn factor -> fn x -> x * factor end end
triple = multiplier.(3)
IO.inspect(triple.(5))

# > **Pitfall:** forgetting the dot. `add(1, 2)` looks
# > for a *named* function `add/2` and fails with
# > `undefined function add/2`. Variables holding
# > functions are always called as `add.(1, 2)`.
#
# > **Pitfall:** `&(&1)` style captures get unreadable
# > fast. If you need `&1` twice or nested captures,
# > write `fn x -> ... end`. Captures can't be nested
# > at all.
