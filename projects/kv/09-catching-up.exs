# Step 8 ended with a gap: a node that joins later starts
# empty, because replication only covers writes made
# while it was a member. This step lets a new replica
# *catch up* before it serves anything: it copies a
# snapshot of the data from a replica that already has
# it.
#
# The order matters. The newcomer first joins the
# `:kv_replicas` group, so every write from then on is
# sent to it too, and only then asks for the snapshot.
# Done the other way round, a write landing between the
# copy and the join would reach neither.
#
# The demo:
#
# 1. Three founding replicas (this node, a and b) take
#    two writes.
# 2. Node c joins and copies its data from b. It reads
#    both keys without ever having seen the writes.
# 3. A write made after c joined reaches c like any
#    other replica.
start_peer = fn name ->
  {:ok, pid, node} = :peer.start_link(%{name: name, host: ~c"127.0.0.1", longnames: true})
  :ok = :erpc.call(node, :code, :add_paths, [:code.get_path()])
  {pid, node}
end

{_peer_a, a} = start_peer.(:kv09_a)
{_peer_b, b} = start_peer.(:kv09_b)
founders = [node(), a, b]

# The replica from step 8, with one change: `start/1`
# takes the node to copy from (`nil` for a founding
# replica). It joins the group in `init/1`, then catches
# up in `handle_continue/2`, which runs before the
# replica handles any message. It asks
# `{__MODULE__, source}`, the replica registered under
# that name on the source node, as on the
# [Leases](/distributed/leases) page. Writes that arrive
# while the snapshot is on its way wait in the mailbox
# and are applied after it, so the snapshot can't
# overwrite them.
{:module, KV, bytecode, _} =
  defmodule KV do
    use GenServer

    def start(source) do
      {:ok, _pid} = GenServer.start(__MODULE__, source, name: __MODULE__)
      :ok
    end

    def put(key, value) do
      for replica <- :pg.get_members(:kv_replicas) do
        :ok = GenServer.call(replica, {:put, key, value})
      end

      :ok
    end

    def get(key), do: GenServer.call(__MODULE__, {:get, key})

    @impl true
    def init(source) do
      :ok = :pg.join(:kv_replicas, self())
      {:ok, %{}, {:continue, {:catch_up, source}}}
    end

    @impl true
    def handle_continue({:catch_up, nil}, map), do: {:noreply, map}

    def handle_continue({:catch_up, source}, _map) do
      {:noreply, GenServer.call({__MODULE__, source}, :snapshot)}
    end

    @impl true
    def handle_call({:put, k, v}, _from, map), do: {:reply, :ok, Map.put(map, k, v)}
    def handle_call({:get, k}, _from, map), do: {:reply, Map.get(map, k), map}
    def handle_call(:snapshot, _from, map), do: {:reply, map, map}
  end

load = fn n ->
  {:module, KV} = :erpc.call(n, :code, :load_binary, [KV, ~c"nofile", bytecode])
  {:ok, _} = :erpc.call(n, :pg, :start, [:pg])
end

{:ok, _} = :pg.start_link()
for n <- [a, b], do: load.(n)
for n <- founders, do: :ok = :erpc.call(n, KV, :start, [nil])

# Group membership spreads between nodes in the
# background, so before writing we wait until this node
# sees the expected number of replicas.
wait_for_replicas = fn again, count ->
  if length(:pg.get_members(:kv_replicas)) == count,
    do: :ok,
    else: Process.sleep(10) && again.(again, count)
end

:ok = wait_for_replicas.(wait_for_replicas, 3)
:ok = KV.put("lang", "elixir")
:ok = KV.put("vm", "beam")

# Node c joins, copying from b. `KV.start/1` returns once
# c has joined the group; the catch-up runs right after,
# and c's first `get` waits behind it in the mailbox.
{_peer_c, c} = start_peer.(:kv09_c)
load.(c)
:ok = :erpc.call(c, KV, :start, [b])
IO.inspect(:erpc.call(c, KV, :get, ["lang"]), label: "c reads lang")
IO.inspect(:erpc.call(c, KV, :get, ["vm"]), label: "c reads vm")

# From now on c is an ordinary replica: once this node
# sees it in the group, writes reach it directly.
:ok = wait_for_replicas.(wait_for_replicas, 4)
:ok = KV.put("otp", "29")
IO.inspect(:erpc.call(c, KV, :get, ["otp"]), label: "c reads otp")

# > **Pitfall:** there is still a gap. `:pg` membership
# > reaches other nodes a moment after c joins. A write
# > started on another node in that moment skips c, and
# > if b had not applied it yet when it took the
# > snapshot, c never gets it. Closing that gap takes a
# > protocol where joining and copying are one step,
# > which is what Mnesia does: the next step.
#
# > **Pitfall:** the snapshot is the whole map, sent in
# > one message. Fine for thousands of keys; for
# > millions, copy in chunks and keep the source
# > responsive between them. Meanwhile every write waits
# > for the newcomer's reply, so a long catch-up slows
# > writes for everyone.
