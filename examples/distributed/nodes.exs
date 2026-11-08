# A *node* is a running BEAM with a name. Named nodes
# can connect to each other and then send messages,
# spawn processes and call functions across machines
# as if everything were local. This script was started
# with `elixir --name nodes@127.0.0.1`, which names the
# node and starts `epmd`, the small daemon nodes use to
# find each other's ports.
IO.inspect(node(), label: "this node")
IO.inspect(Node.alive?(), label: "distributed?")

# In production each node is its own machine or
# container. To try things on one machine, OTP's
# `:peer` module starts extra local nodes linked to
# this one. `longnames: true` gives them *long names*
# like ours: `name@host` with a full host name or IP,
# as `--name` does. `--sname` gives *short names*
# (`name@host` without dots), and a long-name node and
# a short-name node can't connect to each other.
#
# A fresh peer only knows Erlang. The *code path* is
# the list of directories a VM loads compiled modules
# from; `:code.add_paths/1` gives the peer ours, which
# makes Elixir available there.
#
# Nodes only connect if they share a *cookie*, a secret
# atom. Without `--cookie`, the VM reads it from
# `~/.erlang.cookie`, creating that file with a random
# value the first time. The peers run as the same user
# on the same machine, so they read the same cookie.
# `Node.get_cookie/0` returns it; treat it as a
# password and never print or log it.
start_peer = fn name ->
  {:ok, pid, node} = :peer.start_link(%{name: name, host: ~c"127.0.0.1", longnames: true})
  :ok = :erpc.call(node, :code, :add_paths, [:code.get_path()])
  {pid, node}
end

{_pid_a, a} = start_peer.(:nodes_a)
{peer_b, b} = start_peer.(:nodes_b)
IO.inspect(Enum.sort(Node.list()), label: "connected to")

# `:erpc.call/4` runs a function on another node and
# returns its result. Errors on the remote side come
# back as exceptions here.
IO.inspect(:erpc.call(a, :erlang, :node, []), label: "erpc says it ran on")
IO.inspect(:erpc.call(b, System, :version, []), label: "Elixir on b")

# Code does not travel by itself: a module defined in
# this script exists only on this node. `defmodule`
# returns the compiled bytecode, which we load on the
# peers explicitly.
{:module, Echo, bytecode, _} =
  defmodule Echo do
    def loop do
      receive do
        {:ping, from} ->
          send(from, {:pong, node()})
          loop()
      end
    end
  end

for n <- [a, b],
    do: {:module, Echo} = :erpc.call(n, :code, :load_binary, [Echo, ~c"nofile", bytecode])

# `Node.spawn/4` starts a process on another node and
# returns its pid. Sending to a remote pid looks exactly
# like sending to a local one.
echo = Node.spawn(a, Echo, :loop, [])
IO.inspect(node(echo), label: "echo process lives on")
send(echo, {:ping, self()})

receive do
  {:pong, from_node} -> IO.inspect(from_node, label: "pong from")
end

# Nodes fail. `Node.monitor/2` delivers `{:nodedown,
# node}` when a connection is lost, the building block
# for everything that has to survive a machine dying.
Node.monitor(b, true)
:peer.stop(peer_b)

receive do
  {:nodedown, node} -> IO.inspect(node, label: "nodedown")
end

IO.inspect(Enum.sort(Node.list()), label: "still connected to")

# > **Pitfall:** anonymous functions defined in a
# > script can't run on another node:
# > `Node.spawn(a, fn -> ... end)` fails with
# > `UndefinedFunctionError`, because the function's
# > code only exists here. Use module functions
# > (`Node.spawn/4`, `:erpc.call/4`) with modules
# > that are loaded on every node, as a release does.
#
# > **Pitfall:** distribution means full trust. Any
# > node with the cookie can run any code on yours.
# > Never expose `epmd` (port 4369) or distribution
# > ports to the internet; keep nodes on a private
# > network, or use TLS distribution.
#
# > **Pitfall:** connections are transitive but
# > asynchronous. Connect to one node and you will
# > soon be connected to everything it knows, but not
# > instantly. Code that needs a full mesh should check
# > `Node.list/0` or connect explicitly.
