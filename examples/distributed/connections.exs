# `Node.connect/1` looks like one call, but under it is a
# small protocol, and its defaults decide which ports a
# firewall must open, how many connections a cluster
# holds, and why one big message can slow down every
# other message between two nodes. This page looks at
# each of those, with the script as one node
# (`elixir --name connections@127.0.0.1`) and a few
# peers.
start_peer = fn name, args ->
  {:ok, pid, node} =
    :peer.start_link(%{name: name, host: ~c"127.0.0.1", longnames: true, args: args})

  {pid, node}
end

# 1. Finding a node. Every node listens on its own TCP
# port, picked at random by default. EPMD, a small daemon
# on port 4369 of every host, maps node names to those
# ports. Here peer `a` is told to listen on port 9471
# only, and EPMD reports exactly that.
pin_port = [~c"-kernel", ~c"inet_dist_listen_min", ~c"9471", ~c"inet_dist_listen_max", ~c"9471"]
{_, a} = start_peer.(:conn_a, pin_port)
{_, b} = start_peer.(:conn_b, [])

IO.inspect(:erl_epmd.port_please(~c"conn_a", ~c"127.0.0.1"), label: "EPMD: conn_a listens on")

# 2. The cluster is a full mesh. The script started both
# peers, so it's connected to both; `a` and `b` never
# called each other. But when two nodes connect, they
# introduce each other to the rest of the cluster, so
# soon every node is connected to every other. That
# happens in the background, so we wait for it.
nodes_on = fn node, kind -> node |> :erpc.call(:erlang, :nodes, [kind]) |> Enum.sort() end

wait_until = fn check ->
  Stream.repeatedly(fn -> check.() || (Process.sleep(50) && false) end)
  |> Enum.find(& &1)
end

wait_until.(fn -> b in nodes_on.(a, :visible) end)
IO.inspect(nodes_on.(a, :visible), label: "conn_a is connected to")

# With N nodes that's N × (N - 1) / 2 connections, each
# with its own heartbeats. Fine for dozens of nodes,
# heavy for hundreds.
#
# 3. Hidden nodes. A node started with `-hidden` connects
# only to the nodes it talks to directly, isn't passed
# on to the rest of the cluster, and isn't listed by
# `Node.list/0`. Remote shells, monitoring tools and
# `iex --remsh` sessions should connect this way.
{_, h} = start_peer.(:conn_h, [~c"-hidden"])

IO.inspect(Node.list() |> Enum.sort(), label: "Node.list()")
IO.inspect(Node.list(:hidden), label: "Node.list(:hidden)")
IO.inspect(h in nodes_on.(a, :connected), label: "conn_a knows the hidden node")

# 4. One connection per pair. All traffic between two
# nodes, from every process, goes over a single TCP
# connection, and messages from one process to another
# always arrive in the order they were sent. A recorder
# on `b` (plain Erlang calls only: the peers have no
# Elixir loaded) notes the order in which two messages arrive:
# a 20 MB one, then a tiny one.
{:module, Recorder, bytecode, _} =
  defmodule Recorder do
    def record(reply_to, seen) when length(seen) == 2 do
      send(reply_to, {:order, :lists.reverse(seen)})
    end

    def record(reply_to, seen) do
      receive do
        {tag, _payload} -> record(reply_to, [tag | seen])
      end
    end
  end

{:module, Recorder} = :erpc.call(b, :code, :load_binary, [Recorder, ~c"nofile", bytecode])
recorder = Node.spawn(b, Recorder, :record, [self(), []])

send(recorder, {:big, :binary.copy(<<0>>, 20_000_000)})
send(recorder, {:small, "ping"})
receive do: ({:order, order} -> IO.inspect(order, label: "arrived in order"))

# The tiny message waited until all 20 MB had gone
# through. That's *head-of-line blocking*: a process
# sending big terms to a node delays every other
# message to that node, from every process. When the
# connection's send buffer passes this many bytes,
# senders are suspended until it drains:
IO.inspect(:erlang.system_info(:dist_buf_busy_limit), label: "dist buffer busy limit")

# > **Pitfall:** a firewall between nodes must allow EPMD
# > (port 4369) *and* the distribution ports, which are
# > random by default. Pin them with
# > `-kernel inet_dist_listen_min 9100 inet_dist_listen_max 9105`
# > (in a release, in `rel/vm.args.eex`) and open that
# > range.
#
# > **Pitfall:** don't send big terms between nodes on a
# > busy cluster: a large state handoff or a big ETS dump
# > blocks everything else on that connection: calls
# > time out and `:global` and `:pg` updates lag
# > behind. Send big data in chunks, or over a
# > separate channel (HTTP, a shared store).
#
# > **Pitfall:** a full mesh doesn't scale forever. Past
# > a few hundred nodes, split the system into smaller
# > clusters, or connect nodes selectively with
# > `-connect_all false` and hidden nodes.
#
# **Go deeper:** [The BEAM Book](https://blog.stenmans.org/theBeamBook/#CH-Distribution)
# by Erik Stenman covers EPMD, the distribution protocol
# and running distribution at scale (chapters 14 and 15).
