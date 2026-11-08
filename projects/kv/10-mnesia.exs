# Steps 8 and 9 built replication by hand, and step 9
# ended with a gap our protocol can't close: a write can
# slip past a node that is joining. Erlang ships a
# database that solves this: Mnesia. It keeps a table on
# several nodes, writes to all copies in a transaction,
# and when a node joins, copying the table to it and
# starting to send it new writes happen as one step.
#
# This step moves KV's data into a Mnesia table:
#
# 1. Three nodes form a Mnesia cluster and create a
#    table with a copy on each.
# 2. A write on one node is readable on every node.
# 3. Node c joins and gets its own copy of the table,
#    with everything written before it arrived.
# 4. Node a dies; writes carry on, and the surviving
#    copies agree.
#
# The tables here are `ram_copies`: kept in memory only,
# so the demo leaves nothing on disk. Use `disc_copies`
# to keep data across restarts.
start_peer = fn name ->
  {:ok, pid, node} = :peer.start_link(%{name: name, host: ~c"127.0.0.1", longnames: true})
  :ok = :erpc.call(node, :code, :add_paths, [:code.get_path()])
  :ok = :erpc.call(node, :mnesia, :start, [])
  {pid, node}
end

{peer_a, a} = start_peer.(:kv10_a)
{_peer_b, b} = start_peer.(:kv10_b)
:ok = :mnesia.start()

# Each node starts with its own empty Mnesia. Pointing
# this node at a and b (`extra_db_nodes`) merges them
# into one Mnesia cluster with a shared *schema*:
# Mnesia's own table of which tables exist and which
# nodes hold a copy of each.
{:ok, _} = :mnesia.change_config(:extra_db_nodes, [a, b])
IO.inspect(Enum.sort(:mnesia.system_info(:running_db_nodes)), label: "mnesia cluster")

# One table, a copy on every node. Records are tuples
# whose first element is the table name: `{:kv, key,
# value}`. Mnesia's table and transaction functions
# return `{:atomic, result}` on success and
# `{:aborted, reason}` on failure.
nodes = [node(), a, b]
{:atomic, :ok} = :mnesia.create_table(:kv, attributes: [:key, :value], ram_copies: nodes)

# KV's API on top of the table. `put/2` runs in a
# transaction: it commits on every copy or on none. It is
# a `sync_transaction`, which also waits until every
# copy has committed before returning; a plain
# `transaction` may return while other nodes are still
# applying the write. `get/1` reads the local copy
# without a transaction, which is fast and fine for a
# single key.
{:module, KV, bytecode, _} =
  defmodule KV do
    def put(key, value) do
      {:atomic, :ok} = :mnesia.sync_transaction(fn -> :mnesia.write({:kv, key, value}) end)
      :ok
    end

    def get(key) do
      case :mnesia.dirty_read(:kv, key) do
        [{:kv, ^key, value}] -> value
        [] -> nil
      end
    end
  end

load = fn n -> {:module, KV} = :erpc.call(n, :code, :load_binary, [KV, ~c"nofile", bytecode]) end
for n <- [a, b], do: load.(n)

# Step 2: write here, read everywhere. `put/2` returned
# after every copy committed, so there is nothing to
# wait for.
:ok = KV.put("lang", "elixir")
for n <- nodes, do: IO.puts("#{n} reads lang = #{inspect(:erpc.call(n, KV, :get, ["lang"]))}")

# Step 3: node c joins the Mnesia cluster, then asks for
# a copy of the table. `add_table_copy/3` is a schema
# transaction: Mnesia copies the data to c and, from
# then on, writes the table on c too, coordinating the
# copy with writes in progress. That is the part step 9
# couldn't get right.
{_peer_c, c} = start_peer.(:kv10_c)
load.(c)
{:ok, [_ | _]} = :erpc.call(c, :mnesia, :change_config, [:extra_db_nodes, [node()]])
{:atomic, :ok} = :mnesia.add_table_copy(:kv, c, :ram_copies)
IO.inspect(:erpc.call(c, KV, :get, ["lang"]), label: "c reads lang")
IO.inspect(:mnesia.table_info(:kv, :ram_copies) |> Enum.sort(), label: "copies of :kv")

# Step 4: node a dies. Mnesia notices, drops a from the
# running nodes, and transactions carry on with the
# copies that are left.
:peer.stop(peer_a)
:ok = KV.put("vm", "beam")
IO.inspect(:erpc.call(b, KV, :get, ["vm"]), label: "b reads vm after a died")
IO.inspect(:erpc.call(c, KV, :get, ["vm"]), label: "c reads vm after a died")

# > **Pitfall:** Mnesia does not merge after a network
# > partition. If the two sides both take writes, then
# > reconnect, Mnesia reports an
# > `{:inconsistent_database, ...}` system event and
# > leaves both versions in place. Your code has to pick
# > a side (for example with `:mnesia.set_master_nodes/2`
# > and a restart of the other side), so subscribe to
# > these events with `:mnesia.subscribe(:system)`.
#
# > **Pitfall:** every transaction takes locks on all
# > copies, so writes get slower as you add nodes and
# > stall while a node is unreachable but not yet
# > declared down. Keep Mnesia clusters small, and use
# > dirty operations only where you accept their weaker
# > guarantees.
