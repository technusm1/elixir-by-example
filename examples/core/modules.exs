# Named functions live in modules. `def` makes a
# public function, `defp` a private one. `@moduledoc`
# and `@doc` attach documentation; `@spec` declares
# argument and return types (more in
# [Typespecs and Types](/core/typespecs)).
defmodule Temperature do
  @moduledoc "Converts between Celsius and Fahrenheit."

  @doc "Celsius to Fahrenheit."
  @spec to_f(number()) :: float()
  def to_f(c), do: c * 9 / 5 + 32

  @spec to_c(number()) :: float()
  def to_c(f), do: (f - 32) * 5 / 9

  # Multi-line bodies use do/end.
  def describe(c) do
    "#{c}°C is #{format(to_f(c))}°F"
  end

  defp format(value), do: :erlang.float_to_binary(value, decimals: 1)
end

IO.puts(Temperature.describe(100))
IO.inspect(Temperature.to_c(212))

# Private functions can't be called from outside.
# `apply(module, name, args)` calls a function picked
# at runtime, so this compiles and fails when it runs.
try do
  apply(Temperature, :format, [1.0])
rescue
  e in UndefinedFunctionError -> IO.puts(Exception.message(e))
end

# Functions are identified by name *and* arity. Default
# arguments (`\\`) generate the smaller arities for you.
defmodule Greeter do
  def hello(name, punctuation \\ "!") do
    "Hello, #{name}#{punctuation}"
  end

  # Multiple clauses, matched top to bottom.
  def kind(0), do: :zero
  def kind(n) when n > 0, do: :positive
  def kind(_), do: :negative
end

IO.puts(Greeter.hello("Ada"))
IO.puts(Greeter.hello("Ada", "?"))
IO.inspect(Enum.map([0, 5, -5], &Greeter.kind/1))

# Module attributes like `@limit` are constants,
# computed at compile time.
defmodule Limits do
  @limit 3
  def limit, do: @limit
end

IO.inspect(Limits.limit())

# `alias` shortens a module name. `import` lets you
# call functions without the prefix; prefer `only:` so
# readers can see where a function comes from.
alias Temperature, as: T
IO.inspect(T.to_f(0))

import Integer, only: [digits: 1]
IO.inspect(digits(2026))

# > **Pitfall:** `@spec` is documentation and input for
# > tools like Dialyzer, not a runtime check. Elixir
# > 1.20's type checker infers types from your code and
# > guards, but a spec saying `integer()` won't stop
# > someone passing a string.
#
# > **Pitfall:** in a script, you can't `import` (or
# > `use`/`require`) a module defined earlier in the
# > *same* file at top level. It fails to compile with
# > "module Greeter is not loaded but was defined". Move
# > the module to its own file, or call it with its full
# > name.
