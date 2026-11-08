# `=` is the *match* operator. The left side is a
# pattern; Elixir makes it match the right side,
# binding variables along the way.
x = 1
IO.inspect(x)
1 = x
IO.puts("1 = x matched")

# A failed match raises `MatchError`.
try do
  2 = x
rescue
  e in MatchError -> IO.puts(Exception.message(e))
end

# Patterns destructure tuples, lists and maps.
{:ok, result} = {:ok, 42}
[first, second | rest] = [1, 2, 3, 4]
%{name: name} = %{name: "Ada", age: 36}
IO.inspect({result, first, second, rest, name})

# `_` matches anything and binds nothing. Prefixing a
# variable with `_` documents what you ignore.
{_, _status, _} = {:http, 200, "OK"}
{:ok, _value} = {:ok, :ignored}

# Variables can be rebound. To match against a
# variable's *current* value instead, use the pin `^`.
x = 2
IO.inspect(x)

expected = :ok

# `case` tries a value against patterns in order and
# runs the first one that matches (more in
# [Case, Cond and If](/core/case-cond-if)).
case {:ok, "done"} do
  {^expected, msg} -> IO.puts("pinned match: #{msg}")
end

try do
  ^x = 3
rescue
  e in MatchError -> IO.puts(Exception.message(e))
end

# The same variable twice in one pattern must match
# the same value.
{a, a} = {5, 5}
IO.inspect(a)

case {1, 2} do
  {same, same} -> IO.puts("equal")
  {_, _} -> IO.puts("different")
end

# Two more forms you'll meet later. `pattern = var`
# inside a pattern checks the shape *and* binds the
# whole value: `{:ok, _} = reply` keeps all of
# `reply`. `match?(pattern, value)` returns `true` or
# `false` instead of raising.
#
# Matching works in function heads, `case`, `with`,
# and comprehensions. It's the main way Elixir code
# makes decisions. `fn args -> body end` is an
# anonymous function; it can have several clauses,
# tried in order like `case`. Call it with a dot:
# `handle.(x)`.
handle = fn
  {:ok, value} -> "got #{value}"
  {:error, reason} -> "failed: #{reason}"
end

IO.puts(handle.({:ok, 1}))
IO.puts(handle.({:error, :timeout}))

# > **Pitfall:** `=` is not assignment. `{:ok, data} =
# > File.read(path)` crashes on `{:error, :enoent}`.
# > That's fine when failure is a bug, but use `case` or
# > `with` when failure is expected.
#
# > **Pitfall:** inside `case`, a bare variable in a
# > pattern *rebinds*, it doesn't compare. Writing
# > `user_id -> ...` matches anything. Use `^user_id`.
