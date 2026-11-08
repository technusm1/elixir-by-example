# Elixir code goes through a few stages before the BEAM
# runs it, and each one can be looked at from Elixir:
#
# 1. The source is parsed into a tree of plain Elixir
#    data, the *AST* (abstract syntax tree).
# 2. Macros are expanded: `unless`, `|>`, `defstruct`,
#    `use` and most of `def` are macros that rewrite
#    the tree.
# 3. The expanded tree is translated to Erlang's own
#    abstract format and compiled by the Erlang compiler.
# 4. The result is a `.beam` file: bytecode plus named
#    *chunks* of metadata.
#
# Knowing these stages explains error messages that
# mention code you didn't write, and why Elixir and
# Erlang modules can call each other freely.
#
# Stage 1. Every expression is a three-element tuple:
# the operator or function name, metadata (here the
# line), and the arguments. Variables have `nil` as
# their arguments.
IO.inspect(Code.string_to_quoted!("1 + 2 * x"), label: "AST")

# `quote` gives the AST of code written inline.
# `Macro.expand/2` runs one macro and returns the code
# it produces. `unless` turns out to be a `case` with a
# guard that treats both `false` and `nil` as false:
ast = quote do: unless(ok?, do: :retry)
IO.puts(ast |> Macro.expand(__ENV__) |> Macro.to_string())

# Stage 2. The pipe is a macro too. It moves the left
# side into the first argument of the call on its right.
# `Macro.prewalk/2` expands every node in the tree.
piped = quote do: x |> f() |> g(1)
IO.puts(piped |> Macro.prewalk(&Macro.expand(&1, __ENV__)) |> Macro.to_string())

# Stages 3 and 4. `defmodule` returns the compiled
# bytecode, the same bytes `mix compile` writes to a
# `.beam` file.
{:module, Shapes, bytecode, _} =
  defmodule Shapes do
    def area({:square, side}), do: side * side
    def area({:circle, r}) when r > 0, do: 3 * r * r
  end

# `:beam_lib` reads chunks from it. The exports chunk is
# the module's public functions: `area/1`, plus
# `__info__/1` added by Elixir and `module_info/0,1`
# added by Erlang.
{:ok, {Shapes, chunks}} = :beam_lib.chunks(bytecode, [:exports, :debug_info])
IO.inspect(chunks[:exports], label: "exports")

# The debug-info chunk keeps the code in a form tools
# can read back. Asking for it as Erlang shows the
# module as the Erlang compiler saw it: the same clauses
# and guard, with variables renamed.
{:debug_info_v1, backend, data} = chunks[:debug_info]
{:ok, forms} = backend.debug_info(:erlang_v1, Shapes, data, [])

for {:function, _, :area, 1, _} = form <- forms do
  IO.puts(:erl_pp.form(form))
end

# > **Pitfall:** a stack trace or compile error can point
# > at code a macro generated, not code you wrote. When
# > a macro misbehaves, `Macro.expand/2` and
# > `Macro.to_string/1` on its call show what it really
# > produced.
#
# > **Pitfall:** releases strip some chunks to save
# > space, and debug info is what tools like the
# > debugger, `:cover` and Dialyzer read. If a tool
# > can't find a module's code in production, check
# > the `:strip_beams` option of your release.
#
# **Go deeper:** chapter 2 of [The BEAM Book](https://blog.stenmans.org/theBeamBook/#CH-Compiler)
# by Erik Stenman covers the compiler passes, including
# a section on compiling Elixir, and
# [chapter 6](https://blog.stenmans.org/theBeamBook/#CH-beam_modules)
# the `.beam` file format.
