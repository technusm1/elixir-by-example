# `:global` gives a process one name across the whole
# cluster. Every node agrees on who owns the name, so
# it suits singletons: one leader, one scheduler, one
# coordinator. We start two peer nodes as on the Nodes
# page and connect them to each other explicitly, so
# the cluster is fully meshed before we rely on it.
start_peer = fn name ->
  {:ok, pid, node} = :peer.start_link(%{name: name, host: ~c"127.0.0.1", longnames: true})
  :ok = :erpc.call(node, :code, :add_paths, [:code.get_path()])
  {pid, node}
end

{peer_a, a} = start_peer.(:global_a)
{_peer_b, b} = start_peer.(:global_b)
true = :erpc.call(a, Node, :connect, [b])

# Connecting is not enough: each node's `:global` must
# also exchange names with the others, which happens in
# the background. `:global.sync/0` waits for it.
for n <- [node(), a, b], do: :ok = :erpc.call(n, :global, :sync, [])

# A GenServer registered with `name: {:global, ...}`.
# The module has to exist on every node that runs it.
# It uses `GenServer.start/3`, not `start_link`:
# `:erpc.call/4` runs in a short-lived process on the
# remote node, and a process linked to it would die
# with it as soon as the call returns.
{:module, Leader, bytecode, _} =
  defmodule Leader do
    use GenServer
    def start(name), do: GenServer.start(__MODULE__, nil, name: {:global, name})
    @impl true
    def init(nil), do: {:ok, nil}
    @impl true
    def handle_call(:where, _from, state), do: {:reply, node(), state}
  end

for n <- [a, b],
    do: {:module, Leader} = :erpc.call(n, :code, :load_binary, [Leader, ~c"nofile", bytecode])

# Start the leader on node a. Any node can now reach it
# by name, without knowing where it runs.
{:ok, _} = :erpc.call(a, Leader, :start, [:leader])
IO.inspect(GenServer.call({:global, :leader}, :where), label: "leader runs on")
IO.inspect(:erpc.call(b, GenServer, :call, [{:global, :leader}, :where]), label: "b asks, answer")

# The name is unique cluster-wide: a second leader on
# node b is refused, and we learn where the real one is.
{:error, {:already_started, existing}} = :erpc.call(b, Leader, :start, [:leader])
IO.inspect(node(existing), label: "already started on")

# When the owner's node dies, the name is released, so
# another node can take over. That happens when the
# cluster notices the node is gone, a moment later, and
# each node notices on its own. So we wait until both
# this node and b, which will register next, see the
# name free, instead of assuming it is instant.
:peer.stop(peer_a)

wait_until_free = fn again ->
  if Enum.all?([node(), b], &(:erpc.call(&1, :global, :whereis_name, [:leader]) == :undefined)) do
    :free
  else
    Process.sleep(10) && again.(again)
  end
end

IO.inspect(wait_until_free.(wait_until_free), label: "after a died, :leader is")
{:ok, _} = :erpc.call(b, Leader, :start, [:leader])
IO.inspect(GenServer.call({:global, :leader}, :where), label: "new leader runs on")

# > **Pitfall:** registering a name right after nodes
# > connect, before `:global` has synced, can leave the
# > name visible on one node only for a while. Startup
# > code that registers singletons should call
# > `:global.sync/0` first.
#
# > **Pitfall:** every registration takes a lock on all
# > nodes, so it gets slower as the cluster grows. Use
# > `:global` for a few long-lived singletons, not for
# > thousands of short-lived processes: use `Registry`
# > per node, or `:pg` for groups.
#
# > **Pitfall:** after a network partition heals, two
# > nodes may each hold the same name. `:global` then
# > keeps one and, by default, kills the other process.
# > A "singleton" can briefly run twice, so its work
# > must tolerate that (idempotent writes, fencing).
# > [Partitions and Split Brain](/distributed/partitions)
# > shows it happen, and
# > [Leases and Fencing Tokens](/distributed/leases)
# > how to guard against it.
