# On the previous page a `:global` singleton ran twice
# during a network split. The cluster can't prevent that
# on its own: each side only knows what it can see. So
# the decision "who may act" has to live *outside* the
# cluster, in one place every node can reach, such as a
# database row or a Kubernetes Lease.
#
# That decision is a *lease*: a lock that expires. The
# holder must renew it before it runs out. If the holder
# crashes or is cut off, it stops renewing, the lease
# runs out, and another node takes it. Nobody has to tell
# "crashed" from "partitioned"; the clock decides.
#
# A lease alone still isn't enough. A holder can check
# its lease, then freeze (a long garbage collection, a
# suspended VM, a throttled container), wake up after the
# lease expired, and write anyway, sure it's still in
# charge. The fix is a *fencing token*: every time the
# lease changes hands, the store hands out a bigger
# number, the holder sends it with every write, and the
# store rejects writes carrying a smaller number than one
# it has already seen.
#
# The demo, step by step:
#
# 1. Node a takes the lease and gets token 1. Node b
#    asks too and is refused.
# 2. Node a freezes right after checking its lease. Time
#    passes, the lease expires, and b takes it with
#    token 2 and writes a report.
# 3. Node a wakes up and writes its own report, still
#    believing it's the leader. A plain write overwrites
#    b's work. A write with a fencing token is refused.
#
# A third node, `db`, stands in for the database. As on
# the previous page, this script stays outside the
# cluster and drives the nodes over their standard input
# and output. The store keeps its own clock, which this
# script moves forward by hand, so the lease expires at
# exactly the right moment on every run. Only the store's
# clock matters: the holders' clocks may drift, so they
# never decide whether a lease is still valid.
start_peer = fn name ->
  {:ok, peer, node} =
    :peer.start_link(%{
      name: name,
      host: ~c"127.0.0.1",
      longnames: true,
      connection: :standard_io,
      args: ~w(-setcookie leases)c
    })

  :ok = :peer.call(peer, :code, :add_paths, [:code.get_path()])
  {peer, node}
end

{peer_db, db} = start_peer.(:lease_db)
{peer_a, a} = start_peer.(:lease_a)
{peer_b, b} = start_peer.(:lease_b)

# The store: one lease and a few rows, like a table in
# Postgres. `acquire` grants the lease if it's free or
# expired, with the next token, and renews it for its
# current holder. `put/3` is a plain write; `put/4`
# carries a token and is fenced.
{:module, LeaseStore, bytecode, _} =
  defmodule LeaseStore do
    use GenServer

    def start, do: GenServer.start(__MODULE__, nil, name: __MODULE__)

    @impl true
    def init(nil) do
      {:ok, %{now: 0, holder: nil, token: 0, expires: 0, fence: 0, rows: %{}}}
    end

    @impl true
    def handle_call({:acquire, who, ttl}, _from, s) do
      cond do
        s.holder == who and s.now < s.expires ->
          {:reply, {:ok, s.token}, %{s | expires: s.now + ttl}}

        s.holder == nil or s.now >= s.expires ->
          token = s.token + 1
          {:reply, {:ok, token}, %{s | holder: who, token: token, expires: s.now + ttl}}

        true ->
          {:reply, {:error, {:held_by, s.holder}}, s}
      end
    end

    def handle_call({:advance, seconds}, _from, s), do: {:reply, :ok, %{s | now: s.now + seconds}}

    def handle_call({:put, key, value}, _from, s),
      do: {:reply, :ok, %{s | rows: Map.put(s.rows, key, value)}}

    def handle_call({:put, key, value, token}, _from, s) when token >= s.fence,
      do: {:reply, :ok, %{s | fence: token, rows: Map.put(s.rows, key, value)}}

    def handle_call({:put, _key, _value, _token}, _from, s),
      do: {:reply, {:error, :stale_token}, s}

    def handle_call({:get, key}, _from, s), do: {:reply, Map.get(s.rows, key), s}
  end

{:module, LeaseStore} =
  :peer.call(peer_db, :code, :load_binary, [LeaseStore, ~c"nofile", bytecode])

{:ok, _} = :peer.call(peer_db, LeaseStore, :start, [])

# `from.(peer, request)` makes the call *from* that node:
# node a or b talks to the store on node db over Erlang
# distribution, as it would talk to a real database.
from = fn peer, request -> :peer.call(peer, GenServer, :call, [{LeaseStore, db}, request]) end

# Step 1. The lease lasts 10 seconds. Node a gets it with
# token 1; node b is refused while a's lease is valid.
{:ok, token_a} = from.(peer_a, {:acquire, a, 10})
IO.inspect(token_a, label: "a holds the lease, token")
IO.inspect(from.(peer_b, {:acquire, b, 10}), label: "b asks for the lease")

# Step 2. Node a has just checked its lease and is about
# to write when it freezes. While it's frozen, 15 seconds
# pass on the store's clock: a's lease has expired, so b
# gets it, with a bigger token, and writes two copies of
# its report: one plain, one fenced with its token.
:ok = from.(peer_db, {:advance, 15})
{:ok, token_b} = from.(peer_b, {:acquire, b, 10})
IO.inspect(token_b, label: "b holds the lease, token")
:ok = from.(peer_b, {:put, :plain_report, "report by b"})
:ok = from.(peer_b, {:put, :fenced_report, "report by b", token_b})

# Step 3. Node a wakes up. It never saw its lease expire,
# so it writes its reports. The plain write succeeds and
# silently replaces b's report. The fenced write carries
# token 1, the store has already seen token 2, so it is
# refused, and b's report survives.
plain = from.(peer_a, {:put, :plain_report, "report by a"})
fenced = from.(peer_a, {:put, :fenced_report, "report by a", token_a})
IO.inspect(plain, label: "a's plain write")
IO.inspect(fenced, label: "a's fenced write")

IO.inspect(from.(peer_db, {:get, :plain_report}), label: "plain report")
IO.inspect(from.(peer_db, {:get, :fenced_report}), label: "fenced report")

# The refusal is also how a learns it's no longer the
# leader. It should stop working and, if it wants to
# lead again, ask for the lease like everyone else.
IO.inspect(from.(peer_a, {:acquire, a, 10}), label: "a asks again")

# In production the store is something you already run,
# with stronger guarantees than one process:
#
# * **A database row.** A `leases` table with the holder,
#   an expiry and a token that grows on every takeover,
#   updated in a transaction. A fenced write checks, in
#   the same transaction, that no bigger token has been
#   seen. Oban's default leader election,
#   `Oban.Peers.Database`, keeps its leader as a row with
#   an expiry in the `oban_peers` table.
# * **A Kubernetes Lease** (`coordination.k8s.io/v1`).
#   It has `holderIdentity`, `leaseDurationSeconds`,
#   `renewTime`, and `leaseTransitions`, a counter that
#   grows on every change of holder and can serve as the
#   fencing token.
# * **A consensus log** such as `ra` (Raft for Erlang) or
#   Khepri, the replicated store built on `ra` that
#   RabbitMQ uses. No external service, but it only makes
#   progress while a majority of its nodes are up, so
#   clusters usually have 3 or 5 nodes.
#
# > **Pitfall:** the holder must stop *before* its lease
# > runs out, by a safety margin, and renew well before
# > then (the Kubernetes docs give renewing every half
# > lease duration as an example). A holder that acts until the last moment
# > overlaps with the next one as soon as clocks or
# > messages are a little late.
#
# > **Pitfall:** fencing only protects what checks the
# > token. Sending an email, charging a card or calling
# > an API that ignores tokens can still happen twice.
# > Give those an idempotency key (an invoice id, say)
# > so the receiver can drop duplicates.
#
# > **Pitfall:** pre-emptible or spot machines can be
# > frozen or taken away with little warning. That is
# > exactly the "holder froze" case above: plan for it
# > instead of hoping the leader always shuts down
# > cleanly.
#
# > **Pitfall:** libcluster finds nodes and connects
# > them; it doesn't decide who leads. A cluster formed
# > by libcluster splits exactly like the one on the
# > previous page, so singletons still need a lease.
