# Guards add conditions to pattern matches with
# `when`. They work in function heads, `case`, `fn`
# and comprehensions.
#
# Together, function clauses and guards replace most
# `if` chains. Here is a function that handles an
# HTTP-style result, written with `if`. `x in 200..299`
# checks that `x` is in the range, both ends included:
defmodule WithIf do
  def handle(result) do
    if elem(result, 0) == :ok do
      response = elem(result, 1)

      if response.status in 200..299 do
        {:ok, response.body}
      else
        {:error, {:http, response.status}}
      end
    else
      {:error, elem(result, 1)}
    end
  end
end

# The same function as clauses. Each clause is one
# case: the shape it accepts, the condition, the
# result.
defmodule WithClauses do
  def handle({:ok, %{status: status, body: body}}) when status in 200..299, do: {:ok, body}
  def handle({:ok, %{status: status}}), do: {:error, {:http, status}}
  def handle({:error, reason}), do: {:error, reason}
end

results = [
  {:ok, %{status: 200, body: "hi"}},
  {:ok, %{status: 404, body: ""}},
  {:error, :timeout}
]

Enum.each(results, &IO.inspect(WithClauses.handle(&1)))

# A name ending in `?`, like `same?`, marks a boolean
# by convention.
same? = Enum.map(results, &WithIf.handle/1) == Enum.map(results, &WithClauses.handle/1)
IO.inspect(same?, label: "same answers")

# Same answers, but the clause version reads
# differently. The `if` version takes the value apart
# by hand (`elem/2`, `.status`), and you find the
# cases by tracing the nesting. The clause version
# lists every case flat, with its shape visible.
# Handling redirects is one more clause, not another
# level of nesting.
#
# Clauses also fail loudly on input nobody planned
# for. The `if` version quietly sends it down the
# `else` branch and returns a wrong answer:
unexpected = {:retry, 3}
IO.inspect(WithIf.handle(unexpected))

try do
  WithClauses.handle(unexpected)
rescue
  e in FunctionClauseError -> IO.puts(Exception.message(e))
end

# `if` is still the right tool for a single yes/no
# question about a value you already have, like
# `if temp > 30`. Reach for clauses when you are
# checking the *shape* of the data as well.
#
# Guards can also check types, so one function
# handles each kind of input in its own clause.
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
