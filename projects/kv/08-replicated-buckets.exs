# Until now KV lived on one node: if that machine dies,
# so does every key. This step runs a replica of the
# store on every node. Replicas find each other through
# a `:pg` group, every write goes to all of them, and
# reads are answered locally, so any node can serve
# reads even when others are gone.
start_peer = fn name ->
  {:ok, pid, node} = :peer.start_link(%{name: name, host: ~c"127.0.0.1", longnames: true})
  :ok = :erpc.call(node, :code, :add_paths, [:code.get_path()])
  {pid, node}
end

{peer_a, a} = start_peer.(:kv08_a)
{_peer_b, b} = start_peer.(:kv08_b)
nodes = [node(), a, b]

# A replica is a GenServer holding a map, registered
# locally (so each node's own replica is easy to find)
# and joined to the `:kv_replicas` group (so all
# replicas are easy to find). `put/2` is synchronous:
# it returns only after every replica has the value.
{:module, KV, bytecode, _} =
  defmodule KV do
    use GenServer

    def start do
      {:ok, pid} = GenServer.start(__MODULE__, %{}, name: __MODULE__)
      :ok = :pg.join(:kv_replicas, pid)
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
    def init(map), do: {:ok, map}

    @impl true
    def handle_call({:put, k, v}, _from, map), do: {:reply, :ok, Map.put(map, k, v)}
    def handle_call({:get, k}, _from, map), do: {:reply, Map.get(map, k), map}
  end

for n <- [a, b],
    do: {:module, KV} = :erpc.call(n, :code, :load_binary, [KV, ~c"nofile", bytecode])

{:ok, _} = :pg.start_link()
for n <- [a, b], do: {:ok, _} = :erpc.call(n, :pg, :start, [:pg])
for n <- nodes, do: :ok = :erpc.call(n, KV, :start, [])

# Wait until this node sees all three replicas before
# the first write, or the write would miss some.
wait_for_replicas = fn again, count ->
  if length(:pg.get_members(:kv_replicas)) == count,
    do: :ok,
    else: Process.sleep(10) && again.(again, count)
end

:ok = wait_for_replicas.(wait_for_replicas, 3)

# Write on one node, read on every node.
:ok = KV.put("lang", "elixir")
for n <- nodes, do: IO.puts("#{n} reads lang = #{inspect(:erpc.call(n, KV, :get, ["lang"]))}")

# Lose a node: the data survives on the others, and
# writes carry on once the group notices the departure.
:peer.stop(peer_a)
:ok = wait_for_replicas.(wait_for_replicas, 2)
:ok = KV.put("vm", "beam")
IO.inspect(:erpc.call(b, KV, :get, ["vm"]), label: "b reads vm after a died")

# A node that joins later starts empty: replication only
# covers writes made while it was a member.
{_peer_c, c} = start_peer.(:kv08_c)
{:module, KV} = :erpc.call(c, :code, :load_binary, [KV, ~c"nofile", bytecode])
{:ok, _} = :erpc.call(c, :pg, :start, [:pg])
:ok = :erpc.call(c, KV, :start, [])
IO.inspect(:erpc.call(c, KV, :get, ["lang"]), label: "new node c reads lang")

# Two problems remain, and they are the hard part of
# distributed storage. A newcomer has to *catch up* on
# what it missed. And a synchronous write to every
# replica blocks, or fails, as soon as one node is slow
# or unreachable. The next steps tackle both: Mnesia
# for replicated tables that sync new nodes for you, and
# what to do when the network splits the cluster.
