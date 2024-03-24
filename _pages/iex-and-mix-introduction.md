---
title: "Introduction to IEx and Mix"
---

{% contentfor sidebar %}
`iex`, short for `Interactive Elixir` is the Elixir shell. It allows you to execute your elixir code line-by-line.

`mix` is a tool for managing your dependencies and your Elixir projects. As programmers, we carefully **mix** different stuff (i.e. dependencies) to produce amazing **elixirs** (i.e. projects). A good analogy to remember.
{% endcontentfor %}

## IEx introduction

`iex` allows us to type our code line-by-line, and generates the output for it line-by-line. Typing `iex` in your terminal / command prompt will open an interactive elixir shell. Here are some of its features:

- Autocomplete: To discover what functions and modules are available, type anything and press tab to get a list of suggestions.
- History: You can use the up and down arrow keys to browse through the history of commands.
- Expressions: You can type an expression and hit enter to get the result.

`iex` also has a bunch of helper functions that make it easier to work with the IEx shell. We can type `h` and press enter to get a list of all the helper functions. Let's explore a few of them:

- Standard shell-like functions: These include functions like `cd`, `clear`, `ls`, `pwd`, etc.
- Code compilation/information related functions:
  - `c` (compile)
  - `h` (help)
  - `i` (info about last value or given term)
  - `recompile` (the entire project) / `r` (to recompile a single module)
  - `t` (print types for a given module or function)
  - `runtime_info` (get info about the current system and runtime)
  - `v` (return the value of the nth expression in history, or the last expression by default. Can be negative)

> 🔥 **WARNING FROM THE DOCUMENTATION**: Please be aware that the code is truly evaluated in `iex` and not compiled. This means that any benchmarking done in the shell is going to have skewed results. So never run any profiling nor benchmarks in the shell.

## Examples

```elixir
iex> 1 + 2
3
iex> 3 * 4
12
iex> v(-1)
12
iex> v(1)
3
iex> i
Term
  3
Data type
  Integer
Reference modules
  Integer
Implemented protocols
  IEx.Info, Inspect, List.Chars, String.Chars
iex>
```
