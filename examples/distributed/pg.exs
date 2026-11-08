# `:pg` (process groups) lets any number of processes
# join a named group, on any node, and lets anyone look
# up the members. Where `:global` gives one process one
# name, `:pg` gives many processes one name: subscribers
# of a topic, workers of a pool, replicas of a store.
start_peer = fn name ->
  {:ok, pid, node} = :peer.start_link(%{name: name, host: ~c"127.0.0.1", longnames: true})
  :ok = :erpc.call(node, :code, :add_paths, [:code.get_path()])
  {pid, node}
end

{_peer_a, a} = start_peer.(:pg_a)
{peer_b, b} = start_peer.(:pg_b)

# Groups live in a *scope*, a process that must run on
# every node taking part. Here we start the default
# scope, `:pg`, on all three nodes. On the peers it's
# `:pg.start/1`, not `start_link`, as on the Global
# page: a process linked to the short-lived `:erpc`
# caller would die when the call returns.
{:ok, _} = :pg.start_link()
for n <- [a, b], do: {:ok, _} = :erpc.call(n, :pg, :start, [:pg])

# Workers join the `:doublers` group when they start
# and answer requests with the node they run on.
{:module, Doubler, bytecode, _} =
  defmodule Doubler do
    def start, do: spawn(&init/0)

    defp init do
      :ok = :pg.join(:doublers, self())
      loop()
    end

    defp loop do
      receive do
        {:double, x, from} ->
          send(from, {:doubled, node(), x * 2})
          loop()
      end
    end
  end

for n <- [a, b],
    do: {:module, Doubler} = :erpc.call(n, :code, :load_binary, [Doubler, ~c"nofile", bytecode])

# Two workers on a, one on b.
for n <- [a, a, b], do: :erpc.call(n, Doubler, :start, [])

# Membership spreads to other nodes asynchronously, so
# we wait until we can see all three workers.
wait_for_members = fn again, count ->
  case :pg.get_members(:doublers) do
    members when length(members) == count -> members
    _ -> Process.sleep(10) && again.(again, count)
  end
end

members = wait_for_members.(wait_for_members, 3)
IO.inspect(members |> Enum.map(&node/1) |> Enum.sort(), label: "members on")
IO.inspect(length(:erpc.call(a, :pg, :get_local_members, [:doublers])), label: "local to a")

# Fan out: send every member a request and collect one
# reply each. This is how a broadcast or a scatter-gather
# query works on top of `:pg`.
for pid <- members, do: send(pid, {:double, 21, self()})

replies =
  for _ <- members do
    receive do
      {:doubled, from_node, result} -> "#{result} from #{from_node}"
    end
  end

IO.inspect(Enum.sort(replies), label: "replies")

# `:pg.monitor/2` subscribes to joins and leaves. When a
# node goes down, its members leave the group for
# everyone else, and monitors hear about it.
{ref, _current} = :pg.monitor(:pg, :doublers)
:peer.stop(peer_b)

receive do
  {^ref, :leave, :doublers, left} -> IO.inspect(length(left), label: "members that left")
end

IO.inspect(:pg.get_members(:doublers) |> Enum.map(&node/1), label: "members now on")

# > **Pitfall:** `:pg` is eventually consistent. Right
# > after a join, or after a node dies, other nodes may
# > briefly see an old member list. Send with monitors
# > or timeouts, and never assume a member you saw a
# > moment ago is still alive.
#
# > **Pitfall:** `:pg2` is gone. It was deprecated in
# > OTP 23 and removed in OTP 24; calling it now raises
# > `UndefinedFunctionError ... removed in OTP 24. Use
# > 'pg' instead`. Old tutorials and AI assistants still
# > suggest `:pg2.create/1` and `:pg2.join/2`: use `:pg`,
# > which needs no `create` (a group exists once someone
# > joins).
#
# > **Pitfall:** the scope process must run on every
# > node. A node without it simply doesn't take part:
# > no error, just members that never show up. In an
# > application, start `:pg` in your supervision tree
# > on every node.
