# Sometimes all you share between processes is a
# number: a count of requests, a peak, an "already
# done" flag. A GenServer works, but every update is
# a message and a wait. `:atomics` gives you integers
# that any process can change directly, with no
# process and no messages.
#
# `:atomics.new(n, opts)` makes an array of `n`
# 64-bit integers, all zero. Indexes start at 1.
counts = :atomics.new(2, signed: true)
:atomics.put(counts, 1, 10)
:atomics.add(counts, 1, 5)
:atomics.sub(counts, 2, 3)
IO.inspect({:atomics.get(counts, 1), :atomics.get(counts, 2)}, label: "values")

# The array is a reference. Pass it to other
# processes like any value; they all change the same
# integers. A hundred tasks adding 1 each:
hits = :atomics.new(1, [])

1..100
|> Enum.map(fn _ -> Task.async(fn -> :atomics.add(hits, 1, 1) end) end)
|> Task.await_many()

IO.inspect(:atomics.get(hits, 1), label: "hits")

# ## Act on the value you changed
#
# Say at most 3 jobs may run at once. The tempting
# version reads, checks, then adds:
#
#     if :atomics.get(slots, 1) < 3, do: :atomics.add(slots, 1, 1)
#
# Two processes can both read 2, both pass the check
# and both add: 4 jobs running. Between the read and
# the write, anything can happen. (A real race can't
# be shown reliably, so it isn't run here.)
#
# `add_get/3` adds and returns the new value in one
# step that no other process can split. Each caller
# gets a different number, so exactly 3 see a value
# up to 3. The rest take their add back with `sub/3`.
slots = :atomics.new(1, [])

try_start = fn ->
  if :atomics.add_get(slots, 1, 1) <= 3 do
    :started
  else
    :atomics.sub(slots, 1, 1)
    :rejected
  end
end

results = 1..10 |> Enum.map(fn _ -> Task.async(try_start) end) |> Task.await_many()
IO.inspect(Enum.count(results, &(&1 == :started)), label: "started")
IO.inspect(Enum.count(results, &(&1 == :rejected)), label: "rejected")
IO.inspect(:atomics.get(slots, 1), label: "running")

# `sub_get/3` is the same for subtracting, and
# `exchange/3` writes a value and returns the old one.
IO.inspect(:atomics.exchange(slots, 1, 0), label: "exchange returned")
IO.inspect(:atomics.get(slots, 1), label: "now")

# ## compare_exchange: change it only if unchanged
#
# `compare_exchange(ref, i, expected, new)` writes
# `new` only if the value is still `expected`. It
# returns `:ok` on success, or the value it found. A
# one-time flag: ten processes race to run setup, and
# exactly one wins.
flag = :atomics.new(1, [])

winners =
  1..10
  |> Enum.map(fn _ -> Task.async(fn -> :atomics.compare_exchange(flag, 1, 0, 1) end) end)
  |> Task.await_many()
  |> Enum.count(&(&1 == :ok))

IO.inspect(winners, label: "setup ran")

# For anything `add` can't express, loop: read,
# compute, `compare_exchange`, and if someone changed
# the value in between, read again and retry. Keeping
# the largest value ever seen:
defmodule Peak do
  def record(ref, value) do
    current = :atomics.get(ref, 1)

    cond do
      value <= current -> current
      :atomics.compare_exchange(ref, 1, current, value) == :ok -> value
      true -> record(ref, value)
    end
  end
end

peak = :atomics.new(1, [])

[17, 4, 42, 8, 23]
|> Enum.map(fn n -> Task.async(fn -> Peak.record(peak, n) end) end)
|> Task.await_many()

IO.inspect(:atomics.get(peak, 1), label: "peak")

# Atomics aren't owned by a process, unlike an ETS
# table. This array is made by a process that then
# exits, and it keeps working. It's freed once nothing
# references it anymore.
parent = self()
spawn(fn -> send(parent, {:made, :atomics.new(1, [])}) end)
made = receive do: ({:made, ref} -> ref)
:atomics.add(made, 1, 7)
IO.inspect(:atomics.get(made, 1), label: "creator gone")

# ## :counters, for statistics
#
# `:counters` is a cut-down `:atomics` for counting:
# `add`, `sub`, `get` and `put`, always signed. Its
# extra is `:write_concurrency`: adds from many
# schedulers at once get faster, but a `get` that
# runs *during* other adds may see them in any
# order. No add is lost, and a read sees every add
# that finished before it.
stats = :counters.new(2, [:write_concurrency])
[ok, err] = [1, 2]

record = fn n ->
  index = if rem(n, 10) == 0, do: err, else: ok
  :counters.add(stats, index, 1)
end

1..50
|> Enum.map(fn n -> Task.async(fn -> record.(n) end) end)
|> Task.await_many()

IO.inspect({:counters.get(stats, ok), :counters.get(stats, err)}, label: "ok, errors")

# `info/1` returns a map with `size` and an
# approximate `memory` in bytes.
IO.inspect(:counters.info(stats).size, label: "size")

# The default, `[:atomics]`, keeps reads consistent.
# Pick `:counters` for metrics that are mostly
# bumped and rarely read; pick `:atomics` when you
# need `add_get`, `compare_exchange` or unsigned
# values.
#
# ## :persistent_term, read-mostly globals
#
# `:persistent_term` stores any term under a key for
# the whole node. Reads are very fast: the value is
# not copied into the reading process, unlike an ETS
# lookup. Keys are shared by all code on the node, so
# start yours with your app or module name.
key = {:atomics_page, :limits}
:persistent_term.put(key, %{max_jobs: 3, timeout: 5_000})
IO.inspect(:persistent_term.get(key).max_jobs, label: "max_jobs")
IO.inspect(:persistent_term.get({:atomics_page, :none}, :default), label: "missing")

# The catch is on writes. Replacing or erasing a
# value makes *every* process on the node scan its
# heap for the old one, and any process still using
# it gets a full garbage collection that copies it
# in. With many processes, the whole node can become
# less responsive until they're done. So it's for config-like data that is set
# at boot and almost never changes.
#
# A process still holding the old value keeps it
# working after the erase; the VM copies it over.
holder =
  spawn(fn ->
    limits = :persistent_term.get(key)
    send(parent, :got_it)
    receive do: (:show -> send(parent, {:held, limits}))
  end)

receive do: (:got_it -> :ok)
IO.inspect(:persistent_term.erase(key), label: "erased")
IO.inspect(:persistent_term.get(key, :gone), label: "after erase")
send(holder, :show)
receive do: ({:held, limits} -> IO.inspect(limits.max_jobs, label: "holder still has max_jobs"))

# ## Which shared state when?
#
# - **GenServer or Agent**: state with rules, where
#   updates must happen one at a time in order.
# - **ETS**: many keys, read and written by many
#   processes, owned by one.
# - **:atomics / :counters**: plain integers that
#   many processes bump: counts, gauges, flags.
# - **:persistent_term**: a few values read on every
#   request and set about once per boot.
#
# Atomics wrap around instead of growing like Elixir
# integers. One past the largest value is the
# smallest:
wrap = :atomics.new(1, signed: true)
:atomics.put(wrap, 1, 9_223_372_036_854_775_807)
IO.inspect(:atomics.add_get(wrap, 1, 1), label: "signed max + 1")

unsigned = :atomics.new(1, signed: false)
IO.inspect(:atomics.sub_get(unsigned, 1, 1), label: "unsigned 0 - 1")

# > **Pitfall:** atomics and counters wrap around
# > silently at 64 bits, as shown above. An unsigned
# > gauge that is decremented once too often becomes a
# > huge number, not -1.
#
# > **Pitfall:** an index outside `1..n` raises
# > `ArgumentError`. Index 0 is never valid.
#
# > **Pitfall:** a `:persistent_term.put/2` in a hot
# > path (per request, per message) replaces the value
# > each time and can stall the whole node. Store
# > rarely-changing data there; put changing data in
# > ETS or atomics.
#
# > **Pitfall:** an atomics or counters reference only
# > works on the node that created it. Send it to
# > another node and it points at nothing there.
