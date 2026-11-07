# A process registered with `:global` is often used as a
# singleton: one scheduler, one invoice sender, one
# migration runner, work that must happen exactly once.
# The name looks like a guarantee that only one copy
# runs. It isn't. This page makes a singleton run twice
# at the same time, which is what *split brain* means.
#
# It happens when the network between nodes breaks (a
# *partition*). Every node keeps running, but the two
# sides can't see each other. From either side, "the
# other node crashed" and "the network broke" look the
# same, so each side assumes the other is dead.
#
# The demo, step by step:
#
# 1. Two nodes, a and b, share one leader. Jobs from both
#    nodes go to it.
# 2. We cut the network between a and b.
# 3. Node b can no longer see the leader, so it starts
#    its own. Now two leaders run jobs, one on each side.
# 4. We heal the network. `:global` notices the name is
#    taken twice and kills one leader. The cluster looks
#    healthy again, but the jobs the dead leader ran
#    during the split are not accounted for anywhere.
#
# To watch both sides, this script stays *outside* the
# cluster. It isn't a distributed node: it starts the two
# nodes as peers and talks to them over their standard
# input and output (`connection: :standard_io`). Cutting
# the network between a and b can't cut us off from
# either of them.
#
# Each peer gets the same cookie, so they may connect,
# and `dist_auto_connect never`, so they don't reconnect
# by themselves the moment we cut them apart. Logging is
# off on the peers: `:global` logs the name conflict
# below with process ids, which change on every run.
peer_args = ~w(
  -setcookie split
  -kernel dist_auto_connect never
  -kernel logger_level none
)c

start_peer = fn name ->
  {:ok, peer, node} =
    :peer.start_link(%{
      name: name,
      host: ~c"127.0.0.1",
      longnames: true,
      connection: :standard_io,
      args: peer_args
    })

  :ok = :peer.call(peer, :code, :add_paths, [:code.get_path()])
  {peer, node}
end

{peer_a, a} = start_peer.(:split_a)
{peer_b, b} = start_peer.(:split_b)
IO.inspect(Node.alive?(), label: "is this script a node?")

true = :peer.call(peer_a, Node, :connect, [b])
for p <- [peer_a, peer_b], do: :ok = :peer.call(p, :global, :sync, [])
IO.inspect(:peer.call(peer_a, Node, :list, []), label: "a is connected to")

# A singleton registered with `:global`, as on the Global
# Names page. It counts the jobs it has run, standing in
# for real work: sending invoices, running a migration,
# anything that must happen once.
{:module, Leader, bytecode, _} =
  defmodule Leader do
    use GenServer
    def start(name), do: GenServer.start(__MODULE__, 0, name: {:global, name})
    @impl true
    def init(jobs), do: {:ok, jobs}
    @impl true
    def handle_call(:run_job, _from, jobs), do: {:reply, {node(), jobs + 1}, jobs + 1}
  end

for p <- [peer_a, peer_b],
    do: {:module, Leader} = :peer.call(p, :code, :load_binary, [Leader, ~c"nofile", bytecode])

{:ok, leader_a} = :peer.call(peer_a, Leader, :start, [:leader])
job = fn peer -> :peer.call(peer, GenServer, :call, [{:global, :leader}, :run_job]) end
IO.inspect(job.(peer_a), label: "a runs a job on")
IO.inspect(job.(peer_b), label: "b runs a job on")

# Now cut the link. `disconnect_node/1` is the closest a
# single machine gets to unplugging a cable: both nodes
# get a `:nodedown`, as they would if the other side had
# died. Node b learns about it a moment later, so we wait
# until `:global` on b has dropped the name.
true = :peer.call(peer_a, :erlang, :disconnect_node, [b])

wait = fn check, again ->
  if check.(), do: :ok, else: Process.sleep(10) && again.(check, again)
end

b_lost_leader? = fn -> :peer.call(peer_b, :global, :whereis_name, [:leader]) == :undefined end
:ok = wait.(b_lost_leader?, wait)
IO.inspect(:peer.call(peer_b, Node, :list, []), label: "b is connected to")

# From b's side the leader is gone, so b does what any
# failover code would do: it starts a new leader. Both
# succeed. There are now two "singletons", and each side
# keeps running jobs on its own.
{:ok, leader_b} = :peer.call(peer_b, Leader, :start, [:leader])
IO.inspect(job.(peer_a), label: "a runs a job on")
IO.inspect(job.(peer_b), label: "b runs a job on")

# Heal the partition. When the nodes reconnect, `:global`
# finds the name `:leader` registered twice. By default
# it keeps one process and kills the other, picking at
# random, so we only count survivors and don't print
# which side won.
true = :peer.call(peer_b, Node, :connect, [a])
for p <- [peer_a, peer_b], do: :ok = :peer.call(p, :global, :sync, [])

alive = fn ->
  Enum.count([{peer_a, leader_a}, {peer_b, leader_b}], fn {peer, pid} ->
    :peer.call(peer, Process, :alive?, [pid])
  end)
end

:ok = wait.(fn -> alive.() == 1 end, wait)
IO.inspect(alive.(), label: "leaders alive after healing")

same =
  :peer.call(peer_a, :global, :whereis_name, [:leader]) ==
    :peer.call(peer_b, :global, :whereis_name, [:leader])

IO.inspect(same, label: "a and b agree on the leader")

# The cluster is consistent again, but the damage is
# done: for the length of the split, two leaders ran
# jobs, and the survivor knows nothing about the jobs the
# other one ran. A node that pauses for a long garbage
# collection, or is too busy to answer, causes the same
# split without any network fault.
#
# > **Pitfall:** `:global` chooses availability: each
# > side of a split keeps going.
# > That's often right, but a singleton that must never
# > run twice needs something outside the cluster to say
# > who may act: a lease in a database, and a fencing
# > token on every write. That is the next page.
#
# > **Pitfall:** the default conflict handler kills one
# > process with no message to it. Pass your own resolve
# > function to `:global.register_name/3` (for example,
# > keep the one that has done the most work, or tell the
# > loser to hand over its state), and test it by
# > partitioning a real cluster like this.
#
# > **Pitfall:** a node only notices a silent peer after
# > the net tick time (60 seconds by default, set with
# > `-kernel net_ticktime`). Until then, messages to the
# > other side are lost and calls time out. Lower it if failover speed
# > matters, but not so far that a busy node is declared
# > dead.
