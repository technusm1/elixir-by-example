# In every step so far the script connected the nodes
# itself with `Node.connect/1`. A real deployment can't:
# nodes start and stop on their own, get new addresses,
# and come back after a restart. Something on each node
# has to find the others and connect to them, at boot
# and again whenever a connection drops.
#
# libcluster is that something. You give it a
# *topology*: a strategy for finding nodes (a fixed
# list, DNS, the Kubernetes API, UDP gossip) and its
# settings. Each node runs `Cluster.Supervisor` with
# that topology and connects to whatever the strategy
# finds.
#
# The demo:
#
# 1. Three nodes start, not connected to each other.
# 2. Each starts libcluster, and they find each other
#    without any `Node.connect/1` from us.
# 3. We break the connection between two of them, and
#    libcluster connects them again.
#
# libcluster is a Hex package, so the script installs it
# first with `Mix.install/1`. The quiet shell keeps its
# download and compile messages out of the output (so
# the first run is silent for a few seconds); it needs
# Mix started before it can be set.
Mix.start()
Mix.shell(Mix.Shell.Quiet)
Mix.install([{:libcluster, "~> 3.4"}])

# As on the Partitions page, this script stays outside
# the cluster and drives the nodes over stdio, so our
# own connections can't do libcluster's job. Logging is
# off on the nodes: libcluster logs every connection,
# and in an order that changes between runs.
start_peer = fn name ->
  {:ok, peer, node} =
    :peer.start_link(%{
      name: name,
      host: ~c"127.0.0.1",
      longnames: true,
      connection: :standard_io,
      args: ~w(-setcookie kv11 -kernel logger_level none)c
    })

  :ok = :peer.call(peer, :code, :add_paths, [:code.get_path()])
  {peer, node}
end

peers = for name <- [:kv11_a, :kv11_b, :kv11_c], do: start_peer.(name)
[{peer_a, a}, {peer_b, b}, {_peer_c, c}] = peers
connected = fn peer -> peer |> :peer.call(Node, :list, []) |> Enum.sort() end
IO.inspect(connected.(peer_a), label: "a is connected to")

# Step 2. The topology every node runs. `Epmd` is the
# simplest strategy: a fixed list of node names. With a
# `timeout`, it retries the list on that interval, so
# lost connections come back; 100 ms keeps the demo
# short, real deployments use seconds. (`LocalEpmd`,
# which asks this machine's EPMD for every node, would
# also find the nodes of other programs running here.)
#
# The supervisor is started without a link to the
# short-lived process that `:peer.call/4` runs it in;
# in an application it would sit in the supervision
# tree instead.
{:module, KVCluster, bytecode, _} =
  defmodule KVCluster do
    def start(hosts) do
      topologies = [kv: [strategy: Cluster.Strategy.Epmd, config: [hosts: hosts, timeout: 100]]]
      {:ok, pid} = Cluster.Supervisor.start_link([topologies, [name: KVCluster.Supervisor]])
      Process.unlink(pid)
      :ok
    end
  end

hosts = [a, b, c]

for {peer, _} <- peers do
  {:module, KVCluster} = :peer.call(peer, :code, :load_binary, [KVCluster, ~c"nofile", bytecode])
  :ok = :peer.call(peer, KVCluster, :start, [hosts])
end

# Connections are made in the background, so we wait
# until every node sees the other two.
wait = fn check, again ->
  if check.(), do: :ok, else: Process.sleep(10) && again.(check, again)
end

meshed? = fn -> Enum.all?(peers, fn {peer, _} -> length(connected.(peer)) == 2 end) end
:ok = wait.(meshed?, wait)
for {peer, n} <- peers, do: IO.puts("#{n} is connected to #{inspect(connected.(peer))}")

# Step 3. Break the connection between a and b, as a
# network blip would. Within the timeout, libcluster
# connects them again, and we wait until every node
# sees the other two once more.
true = :peer.call(peer_a, :erlang, :disconnect_node, [b])
:ok = wait.(meshed?, wait)
IO.inspect(connected.(peer_a), label: "a is connected to, after the blip")

# libcluster connects nodes; that's all it does. It
# doesn't copy data, elect a leader or heal a split:
# KV on a node that libcluster just connected still
# needs `:mnesia.add_table_copy/3` (step 10) before it
# holds any data, and singletons still need leases (see
# the Leases page).
#
# > **Pitfall:** in production the list of nodes isn't
# > fixed. On Kubernetes use `Kubernetes.DNS` or
# > `Kubernetes` (the API) strategies with a headless
# > service; elsewhere `DNSPoll`. Every node must use
# > the same cookie and node naming scheme, or
# > libcluster finds them and the connections are
# > refused.
#
# > **Pitfall:** `Gossip` (UDP multicast) is easy
# > locally but most cloud networks drop multicast, and
# > anyone on the network segment with your cookie can
# > join. Prefer a strategy backed by your platform's
# > own idea of which nodes exist.
