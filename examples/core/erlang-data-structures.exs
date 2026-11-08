# Elixir runs on the Erlang VM, and every Erlang
# module is yours to call. An Erlang module's name is
# a plain atom, so `:queue.new()` calls the `new`
# function in Erlang's `queue` module. Erlang's docs
# write it `queue:new()`.
q = :queue.new()
IO.inspect(:queue.is_empty(q), label: "empty?")

# Erlang's standard library has a few data structures
# Elixir doesn't. This page covers the ones worth
# knowing and when each one beats a list or a map.
#
# First, a difference in style. Elixir functions take
# the "subject" first, so they pipe. Many Erlang
# functions take the item first and the collection
# *last*: `:queue.in(item, queue)`. Pipe a queue into
# it and the queue lands in the item slot, so the
# call raises `ArgumentError`.
try do
  :queue.new() |> :queue.in(1)
rescue
  e in ArgumentError -> IO.puts("piped: " <> Exception.message(e))
end

# So with Erlang modules, bind each step to a
# variable instead of piping.
q = :queue.in(1, :queue.new())
IO.inspect(:queue.to_list(q), label: "bound")

# ## :queue, a first-in first-out line
#
# A list is a poor queue: taking from the front is
# cheap, but adding to the back copies the whole list.
# `:queue` keeps two lists, a front and a reversed
# rear. `in/2` pushes onto the rear, `out/1` pops the
# front, and only when the front runs dry is the rear
# reversed into place. Each item gets reversed once,
# so both operations are cheap on average.
q = :queue.new()
q = :queue.in(:a, q)
q = :queue.in(:b, q)
q = :queue.in(:c, q)
IO.inspect(:queue.to_list(q), label: "front to rear")
IO.inspect(:queue.len(q), label: "len")

# `out/1` returns the item *and* the new queue. The
# item comes wrapped as `{:value, item}`, so a stored
# `nil` or `:empty` can't be confused with "nothing
# there".
{{:value, first}, q} = :queue.out(q)
IO.inspect(first, label: "out")
IO.inspect(:queue.to_list(q), label: "left")

# On an empty queue you get `{:empty, queue}` instead.
# Match on both shapes with `case`; this is the loop
# you'll see in GenServers that hold a queue.
defmodule Drain do
  def all(q, acc \\ []) do
    case :queue.out(q) do
      {{:value, item}, rest} -> all(rest, [item | acc])
      {:empty, _q} -> Enum.reverse(acc)
    end
  end
end

IO.inspect(Drain.all(q), label: "drained")

# `peek/1` looks at the front without removing it,
# and returns `{:value, item}` or a bare `:empty`.
IO.inspect(:queue.peek(q), label: "peek")
IO.inspect(:queue.peek(:queue.new()), label: "peek empty")

# It's double-ended: `in_r/2` pushes onto the front
# (a "jump the line" item) and `out_r/1` pops from
# the rear.
q = :queue.from_list([2, 3])
q = :queue.in_r(1, q)
IO.inspect(:queue.to_list(q), label: "in_r")
{{:value, last}, q} = :queue.out_r(q)
IO.inspect({last, :queue.to_list(q)}, label: "out_r")

# Use it when: work arrives at one end and leaves at
# the other, like jobs waiting for a worker or
# callers waiting for room.
#
# ## :gb_trees, a sorted key-value store
#
# Map keys have no order you should rely on.
# `:gb_trees` (general balanced trees) keeps keys
# sorted, so "smallest", "largest" and "first key
# after X" are cheap. Here, timers keyed by
# `{due_at, name}`: tuples compare element by element,
# so they sort by time, then by name.
timers =
  Enum.reduce(
    [{{30, :flush}, "write buffer"}, {{10, :ping}, "health check"}, {{20, :ping}, "retry"}],
    :gb_trees.empty(),
    fn {key, job}, tree -> :gb_trees.enter(key, job, tree) end
  )

IO.inspect(:gb_trees.to_list(timers), label: "in order")
IO.inspect(:gb_trees.smallest(timers), label: "next due")
IO.inspect(:gb_trees.largest(timers), label: "last due")

# `take_smallest/1` pops the next timer and returns
# the rest of the tree. `lookup/2` reads one key.
{key, job, timers} = :gb_trees.take_smallest(timers)
IO.inspect({key, job}, label: "fired")
IO.inspect(:gb_trees.lookup({20, :ping}, timers), label: "lookup")
IO.inspect(:gb_trees.lookup({99, :nope}, timers), label: "missing")

# An iterator walks keys in order, and
# `iterator_from/2` starts at the first key greater
# than or equal to the one you give. `next/1` returns
# `{key, value, iterator}`, or `:none` at the end.
# "First key at or after X" is how a hash ring finds
# the node that owns a key.
ring = :gb_trees.from_orddict([{100, :node_a}, {200, :node_b}, {300, :node_c}])

owner = fn hash ->
  case :gb_trees.next(:gb_trees.iterator_from(hash, ring)) do
    {_point, node, _iter} -> node
    :none -> elem(:gb_trees.smallest(ring), 1)
  end
end

IO.inspect(Enum.map([50, 200, 250, 350], owner), label: "owners")

# `enter/3` inserts or replaces. `insert/3` refuses a
# key that is already there, which catches bugs.
try do
  :gb_trees.insert({20, :ping}, "again", timers)
rescue
  e in ErlangError -> IO.inspect(e.original, label: "insert")
end

# Use it when: you need keys in order, the smallest
# or largest key, or the next key after a value.
#
# ## :gb_sets, a sorted set
#
# The same tree without values. A pool of free ids
# that always hands out the lowest one:
free = :gb_sets.from_list([4, 2, 7])
{id, free} = :gb_sets.take_smallest(free)
IO.inspect(id, label: "handed out")
free = :gb_sets.add(1, free)
IO.inspect(:gb_sets.to_list(free), label: "free ids")
IO.inspect(:gb_sets.is_member(4, free), label: "4 free?")

# Use it when: a set must stay sorted. For plain
# membership, Elixir's `MapSet` (an unordered set of
# unique values) is the usual choice.
#
# ## :digraph, a graph
#
# `:digraph` stores vertices and edges, and
# `:digraph_utils` runs graph algorithms on it.
# Unlike everything else on this page it's *mutable*:
# it lives in ETS tables (shared in-memory tables,
# covered in the OTP track), so `add_vertex/2`
# changes `g` in place and returns no new graph.
g = :digraph.new([:acyclic])
for app <- [:app, :web, :db], do: :digraph.add_vertex(g, app)
:digraph.add_edge(g, :app, :web)
:digraph.add_edge(g, :web, :db)
:digraph.add_edge(g, :app, :db)

# A topological sort puts every vertex before the
# ones its edges point to: an order to start apps
# that depend on each other, read backwards.
IO.inspect(:digraph_utils.topsort(g), label: "topsort")

# Created with `:acyclic`, it refuses an edge that
# would close a loop, returning the existing path
# (`:app` to `:db`) that the new edge would turn into
# a cycle.
IO.inspect(:digraph.add_edge(g, :db, :app), label: "cycle")

# Being mutable, it must be freed by hand.
:digraph.delete(g)

# Use it when: you have real graph questions (paths,
# cycles, ordering) and can live with mutable state.
#
# ## Which one?
#
# - **List**: items in order, read front to back.
#   Adding to the front is cheap; to the back, not.
# - **Map**: lookup by key, no order.
# - **MapSet**: "have I seen this?", no order.
# - **:queue**: first in, first out, at both ends.
# - **:gb_trees** / **:gb_sets**: sorted keys,
#   smallest, largest, ranges.
# - **:digraph**: vertices and edges.
#
# Erlang also has `:array`, a functional array of
# integer-indexed slots with a default value. In
# Elixir a map with integer keys or a tuple usually
# reads better, so it's rarely worth reaching for.

# > **Pitfall:** a queue's inner shape (two lists) is
# > documented as opaque. Don't match on it or build
# > one by hand; use `:queue.is_empty/1`, `out/1` and
# > friends.
#
# > **Pitfall:** `:queue.len/1` walks the whole queue,
# > because queues don't store their length. If you
# > check the length on every call of a long queue,
# > keep a count next to it.
#
# > **Pitfall:** `:gb_trees.enter/3` overwrites an
# > existing key without a word. Two timers due at the
# > same moment would collide on a bare `due_at` key;
# > that's why the example keys on `{due_at, name}`.
