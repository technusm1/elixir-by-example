---
title: "Introduction to IEx"
---

{% contentfor sidebar %}
`iex`, short for `Interactive Elixir` is the Elixir shell. It allows you to execute your elixir code line-by-line.
{% endcontentfor %}

## IEx introduction

`iex` allows us to type our code line-by-line, and executes it one line at a time. Typing `iex` in your terminal / command prompt will open an interactive elixir shell. Here are some of its features:

- **Autocomplete**: To discover what functions and modules are available, type anything and press tab to get a list of suggestions.
- **History**: You can use the up and down arrow keys to browse through the history of commands.
- **Expressions**: You can type an expression and hit enter to evaluate it and get its result.

`iex` also provides some helper functions that make it easier to work with. We can type `h` and press enter to get a list of all the helper functions. Let's explore a few of them:

- **Standard shell-like functions**: These include functions like `cd`, `clear`, `ls`, `pwd`, etc. If you've ever used a unix-like shell, you know what they do.
- Code compilation / information related functions:
  - `c` (compile)
  - `h` (help)
  - `i` (info about last value or given term)
  - `recompile` (the entire project) / `r` (to recompile a single module)
  - `t` (print types for a given module or function)
  - `runtime_info` (get info about the current system and runtime)
  - `v` (return the value of the nth expression in history, or the last expression by default. Can be negative)

> 🔥 **WARNING FROM THE DOCUMENTATION**: Please be aware that the code is truly evaluated line-by-line in `iex` and not compiled. This means that any benchmarking done in the shell is going to have skewed results, since compilers can optimize the code they're building, but a code executing line-by-line isn't optimized by `iex`. So it is recommended not to run any profiling or any benchmarks in the shell.

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
