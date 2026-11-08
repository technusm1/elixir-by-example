# Elixir has a handful of basic value types. Integers
# have arbitrary precision, so they never overflow.
IO.inspect(1 + 2)
IO.inspect(2 ** 100)
IO.inspect(1_000_000)

# `/` always returns a float. Use `div/2` and `rem/2`
# for integer division.
IO.inspect(10 / 2)
IO.inspect(div(10, 3))
IO.inspect(rem(10, 3))

# Floats are 64-bit doubles, with the usual rounding
# surprises.
IO.inspect(0.1 + 0.2)
IO.inspect(Float.round(0.1 + 0.2, 2))

# Booleans are `true` and `false`. `and`, `or` and
# `not` require booleans; `&&`, `||` and `!` accept any
# value. Only `nil` and `false` are falsy.
IO.inspect(true and false)
IO.inspect(nil || "default")
IO.inspect(0 && "zero is truthy")

# Strings are UTF-8 and use double quotes. `<>`
# concatenates, `#{}` interpolates.
name = "world"
IO.puts("hello " <> name)
IO.puts("1 + 1 = #{1 + 1}")

# Comparisons work across types. `==` compares
# numbers by value, `===` also checks the type.
IO.inspect(1 == 1.0)
IO.inspect(1 === 1.0)
# `:atom` is an atom, a named constant (next page).
IO.inspect(1 < :atom)

# Check types with the `is_*` functions.
IO.inspect(is_integer(42))
IO.inspect(is_float(42))
IO.inspect(is_binary("text"))

# > **Pitfall:** `0`, `""` and `[]` are *truthy*. Code
# > ported from JavaScript or Python that relies on
# > `if list do` to mean "non-empty" is wrong in Elixir;
# > use `list != []` or pattern match on `[_ | _]`.
#
# > **Pitfall:** never compare money or IDs as floats.
# > `0.1 + 0.2 == 0.3` is `false`. Use integers (cents)
# > or the `Decimal` library.
