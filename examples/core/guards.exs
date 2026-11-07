# Guards add conditions to pattern matches with
# `when`. They work in function heads, `case`, `fn`
# and comprehensions.
defmodule Shape do
  def area({:circle, r}) when is_number(r) and r >= 0, do: 3.14159 * r * r
  def area({:rect, w, h}) when is_number(w) and is_number(h), do: w * h
  def area(other), do: {:error, {:unknown_shape, other}}
end

IO.inspect(Shape.area({:circle, 2}))
IO.inspect(Shape.area({:rect, 3, 4}))
IO.inspect(Shape.area({:circle, -1}))

# Only a fixed set of expressions is allowed in guards:
# comparisons, boolean operators, arithmetic, type
# checks (`is_*`) and a few functions like
# `length/1`, `map_size/1`, `elem/2`, `is_map_key/2`.
check = fn
  list when is_list(list) and length(list) > 2 -> :long_list
  map when is_map(map) and is_map_key(map, :id) -> :has_id
  bin when is_binary(bin) and byte_size(bin) == 0 -> :empty_string
  _ -> :other
end

IO.inspect(Enum.map([[1, 2, 3], %{id: 1}, "", 42], check))

# `in` with a literal list or range works in guards.
weekday? = fn
  day when day in [:sat, :sun] -> false
  _ -> true
end

IO.inspect({weekday?.(:mon), weekday?.(:sun)})

# An error inside a guard doesn't raise; the guard
# just fails and the next clause is tried.
safe = fn
  x when hd(x) == :a -> :starts_with_a
  _ -> :no
end

IO.inspect(safe.(:not_a_list))

# Name reusable guards with `defguard`.
defmodule Checks do
  defguard is_even(n) when is_integer(n) and rem(n, 2) == 0
end

defmodule Parity do
  import Checks
  def of(n) when is_even(n), do: :even
  def of(n) when is_integer(n), do: :odd
end

IO.inspect(Enum.map(1..4, &Parity.of/1))

# > **Pitfall:** you can't call your own functions in a
# > guard (`when valid?(x)` is a compile error). Use
# > `defguard`, or match first and check in the body.
#
# > **Pitfall:** an error anywhere in a guard fails the
# > *whole* guard. `when map_size(x) == 0 or is_list(x)`
# > does not match a list, because `map_size/1` raises
# > first. Chain `when` clauses instead (`when
# > map_size(x) == 0 when is_list(x)`): each one is
# > tried on its own.
