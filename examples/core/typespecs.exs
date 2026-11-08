# Elixir has two kinds of types. *Typespecs* are
# annotations you write: documentation for readers and
# input for tools like Dialyzer. The *type checker*
# built into the compiler (Elixir 1.17 and later)
# needs no annotations at all: it infers types from
# your code and warns about calls that can never work.
#
# Start with typespecs. `@type` names a type, `@spec`
# describes a function. By convention a struct's
# module defines `t()`, the type of the struct itself.
defmodule Order do
  @enforce_keys [:id]
  defstruct [:id, status: :pending, items: []]

  # A union of literal atoms, written with `|`.
  @type status :: :pending | :paid | :shipped

  # A map type: `required(...)` keys must be present,
  # `optional(...)` keys may be. `String.t()` is a
  # UTF-8 string; `pos_integer()` is 1, 2, 3...
  @type item :: %{
          required(:sku) => String.t(),
          required(:qty) => pos_integer(),
          optional(:gift) => boolean()
        }

  # `%__MODULE__{...}` is this struct, with a type for
  # each field. `[item()]` is shorthand for
  # `list(item())`.
  @type t :: %__MODULE__{
          id: pos_integer(),
          status: status(),
          items: [item()]
        }

  # `@typep` is private: usable only inside this
  # module, and hidden from the docs.
  @typep count :: non_neg_integer()

  # `keyword()` is a keyword list, like the options
  # here.
  @spec new(pos_integer(), [item()], keyword()) :: t()
  def new(id, items, opts \\ []) do
    struct!(__MODULE__, [id: id, items: items] ++ opts)
  end

  @spec quantity(t()) :: count()
  def quantity(order), do: order.items |> Enum.map(& &1.qty) |> Enum.sum()

  @spec half(integer()) :: integer()
  def half(n), do: n / 2
end

order = Order.new(1, [%{sku: "TEA", qty: 2}, %{sku: "MUG", qty: 1, gift: true}])
IO.inspect(order)
IO.inspect(Order.quantity(order), label: "quantity")

# Specs are *not* enforced. The compiler stores them in
# the module for docs and tools, and that's all.
# `half/1` promises an integer and returns a float.
IO.inspect(Order.half(3), label: "half(3)")

# Dialyzer is the classic tool that reads specs and
# hunts for contradictions. It's an optional extra,
# usually added to a project through the `dialyxir`
# package. The type checker below is different: it is
# part of the compiler and runs on every build.
#
# The checker grew release by release: 1.17 inferred
# types from patterns, 1.18 checked function calls,
# 1.19 added anonymous functions and protocols, and
# 1.20 infers types for whole functions, guards
# included.
#
# Type errors are compiler *warnings*. To show them on
# this page, `Checker` compiles a snippet with
# `Code.compile_string/1` and captures the diagnostics
# with `Code.with_diagnostics/1` instead of letting
# them print. It keeps each message up to the "where"
# section, which lists source locations. (`~r/.../`
# is a regex; the [Sigils](/core/sigils) page covers
# both it and `~S`.)
defmodule Checker do
  def check(title, source) do
    {_modules, diagnostics} = Code.with_diagnostics(fn -> Code.compile_string(source) end)
    IO.puts("== #{title}")

    if diagnostics == [] do
      IO.puts("    (no warnings)")
    end

    for %{message: message} <- diagnostics do
      [kept | _] = String.split(message, "\nwhere ")
      kept |> String.trim() |> String.replace(~r/^(?=.)/m, "    ") |> IO.puts()
    end
  end
end

# The classic bug: a function returns `{:ok, order}`
# and the caller forgets to unwrap it. The compiler
# infers from the pattern that `ship/1` needs a map
# with `status: :paid`, and a tuple never is one.
# Without colors, the mismatched part is marked with
# `-...-`. Each snippet is a `~S"""` string: a
# multi-line string that leaves `#{...}` alone, so
# the code inside isn't interpolated.
Checker.check("forgot to unwrap {:ok, _}", ~S"""
defmodule Shipping do
  def ship(%{status: :paid} = order), do: {:shipped, order}

  def run, do: ship({:ok, %{status: :paid}})
end
""")

# A misspelled field. `%Order{}` in the pattern tells
# the checker the exact keys, so `order.stauts` can
# never work.
Checker.check("typo in a struct field", ~S"""
defmodule Report do
  def line(%Order{} = order), do: "order #{order.id}: #{order.stauts}"
end
""")

# Since 1.20 the checker infers types from guards and
# from what the body does with a value. `total/1` only
# multiplies, so it needs numbers, and a price straight
# from a form is a string.
Checker.check("a string where a number goes", ~S"""
defmodule Pricing do
  def total(line), do: line.price * line.qty

  def run, do: total(%{price: "9.99", qty: 2})
end
""")

# Return types are inferred too. `parse_qty/1` returns
# `{:ok, n}` or `:error`, never `nil`, so the `nil`
# clause in its caller is dead code.
Checker.check("a case clause that can never match", ~S"""
defmodule Form do
  defp parse_qty("one"), do: {:ok, 1}
  defp parse_qty(_), do: :error

  def qty(input) do
    case parse_qty(input) do
      {:ok, n} -> n
      :error -> 0
      nil -> 1
    end
  end
end
""")

# Also new in 1.20: a clause that earlier clauses
# already cover is reported as redundant.
Checker.check("a redundant clause", ~S"""
defmodule Labels do
  def label(s) when is_binary(s), do: s
  def label(a) when is_atom(a), do: Atom.to_string(a)
  def label(s) when is_binary(s), do: String.upcase(s)
end
""")

# The checker reads code, not specs. Here the spec
# says integer, the guard says string, and only the
# guard counts. The wrong spec itself goes unreported.
Checker.check("the guard wins over the spec", ~S"""
defmodule Shout do
  @spec shout(integer()) :: String.t()
  def shout(s) when is_binary(s), do: String.upcase(s)

  def run, do: shout(42)
end
""")

# It is *gradual*: a value it knows nothing about has
# type `dynamic()`, and it only warns when a call fails
# for *every* type it could be. Input from outside
# (JSON, user input, a message) stays unchecked until
# runtime, where the bad call still fails.
Checker.check("unknown input is not checked", ~S"""
defmodule Inbox do
  def ship(%{status: :paid} = order), do: {:shipped, order}

  def handle(input), do: ship(input)
end
""")

try do
  Inbox.handle(:oops)
rescue
  e in FunctionClauseError -> IO.puts("FunctionClauseError: " <> Exception.message(e))
end

# So: write `@spec` and `@type` for public functions
# and structs, as documentation that tools can read.
# Let the compiler's inference catch bugs everywhere
# else; it needs nothing from you. Add Dialyzer if you
# want a second opinion.
#
# > **Pitfall:** a spec that lies is never caught by
# > the compiler. `half/1` above returns a float under
# > an `integer()` spec, and the checker ignores specs
# > entirely in Elixir 1.20 (its docs list function
# > signatures as a future milestone). Dialyzer is
# > the tool that compares specs with code.
#
# > **Pitfall:** `any()` and `term()` are the same
# > typespec type: any value at all. Don't confuse
# > them with `dynamic()` in the checker's messages
# > (`dynamic(%Order{...})` above). It marks a type
# > the checker only partly knows, and it stays quiet
# > about calls such a value *might* satisfy.
#
# > **Pitfall:** no warning doesn't mean correct.
# > The checker reports only calls that fail for every
# > possible type, so `Inbox.handle/1` compiled
# > silently and still crashed at runtime. Pattern
# > match on input at the edges of your system, where
# > it comes in.
