# Across these steps we build **KV**, a small
# key-value store, and keep growing it: concurrent,
# supervised, cached in ETS, expiring keys, and later
# distributed across nodes. Each step reuses ideas from
# the concept pages linked above.
#
# Step one: an immutable map already *is* a store. We
# only need a module that names the operations, so
# callers don't depend on the representation.
defmodule KV do
  def new, do: %{}

  def put(store, key, value), do: Map.put(store, key, value)

  def get(store, key, default \\ nil), do: Map.get(store, key, default)

  def delete(store, key), do: Map.delete(store, key)

  def keys(store), do: store |> Map.keys() |> Enum.sort()
end

# Every operation returns a *new* store. Nothing is
# mutated, so there's no way for two parts of a
# program to step on each other's data.
store =
  KV.new()
  |> KV.put("lang", "elixir")
  |> KV.put("vm", "beam")
  |> KV.put("year", 2012)

IO.inspect(KV.get(store, "lang"), label: "lang")
IO.inspect(KV.get(store, "missing", :none), label: "missing")
IO.inspect(KV.keys(store), label: "keys")

# Old versions stay valid. This is what makes
# immutable data easy to reason about, and later it's
# what makes undo, snapshots and replication cheap.
older = store
store = KV.delete(store, "year")
IO.inspect(KV.keys(older), label: "older")
IO.inspect(KV.keys(store), label: "now")

# The catch: a value only lives as long as the
# variable that holds it. Two processes can't share
# this store, and nothing outlives the function that
# created it. In the OTP track, step 4 fixes that by
# putting the store inside a process.
