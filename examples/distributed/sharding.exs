# When data is spread over several nodes, every key
# needs one owner, and every node has to agree which one
# it is without asking anybody. The answer is a hash
# function: hash the key, map the hash to a node.
#
# The obvious mapping is `hash mod number_of_nodes`. It
# spreads keys evenly, and it falls apart the moment the
# cluster changes size: almost every key gets a new
# owner, so almost all the data has to move.
#
# `:erlang.phash2/1` hashes any term to an integer. It
# gives the same hash for the same term on every node
# and every platform, which is exactly what agreeing
# without talking needs. `:erlang.phash2/2` takes a
# range `n` and returns a hash from 0 to `n - 1`.
keys = for n <- 1..10_000, do: "user:#{n}"
four = [:a, :b, :c, :d]
five = four ++ [:e]

mod_owner = fn key, nodes -> Enum.at(nodes, rem(:erlang.phash2(key), length(nodes))) end

moved = fn owner, before, later ->
  Enum.count(keys, fn key -> owner.(key, before) != owner.(key, later) end)
end

IO.inspect(moved.(mod_owner, four, five), label: "mod: keys moved going from 4 to 5 nodes")

# *Consistent hashing* puts nodes on a ring of hash
# values. A key belongs to the first node at or after
# its own hash, going round. A new node takes over one
# stretch of the ring, so only the keys in that stretch
# move: about one in five when going from four nodes to
# five.
#
# Each node goes on the ring many times (*virtual
# nodes*), under different hashes, to even out the
# load (more on that below). A `:gb_trees` (see
# [Erlang Data Structures](/core/erlang-data-structures))
# keeps the points sorted, and `iterator_from/2` finds
# the first point at or after a hash without scanning
# the ring.
defmodule Ring do
  @range 4_294_967_296

  def new(nodes, vnodes \\ 100) do
    points = for node <- nodes, i <- 1..vnodes, do: {hash({node, i}), node}

    Enum.reduce(points, :gb_trees.empty(), fn {h, node}, tree ->
      :gb_trees.enter(h, node, tree)
    end)
  end

  def owner(ring, key) do
    case :gb_trees.next(:gb_trees.iterator_from(hash(key), ring)) do
      {_hash, node, _iter} -> node
      # Past the last point: wrap round to the first.
      :none -> elem(:gb_trees.smallest(ring), 1)
    end
  end

  # Hashes from 0 to 2^32 - 1: a 32-bit ring.
  defp hash(term), do: :erlang.phash2(term, @range)
end

rings = %{four => Ring.new(four), five => Ring.new(five)}
ring_owner = fn key, nodes -> Ring.owner(rings[nodes], key) end

IO.inspect(moved.(ring_owner, four, five), label: "ring: keys moved going from 4 to 5 nodes")

# The keys that moved all moved *to* the new node. No
# key moved between two old nodes, so the old nodes
# only hand data over; they never shuffle it among
# themselves.
movers = Enum.filter(keys, fn key -> ring_owner.(key, four) != ring_owner.(key, five) end)
IO.inspect(movers |> Enum.map(&ring_owner.(&1, five)) |> Enum.uniq(), label: "moved to")

# How even the shares are depends on the number of
# points per node. With one point each, one node can
# own three times as much as another. More points even
# it out, for a bigger ring.
for vnodes <- [1, 10, 100, 1000] do
  ring = Ring.new(five, vnodes)
  shares = keys |> Enum.frequencies_by(&Ring.owner(ring, &1)) |> Map.values()
  IO.puts("points per node #{vnodes}: #{Enum.min(shares)} to #{Enum.max(shares)} keys each")
end

# *Rendezvous hashing* gets the same property with no
# ring at all: score every node for the key and take the
# highest. A new node wins exactly the keys where it
# scores best. It costs one hash per node per lookup,
# which is nothing for a handful of nodes.
rendezvous = fn key, nodes -> Enum.max_by(nodes, &:erlang.phash2({key, &1})) end
IO.inspect(moved.(rendezvous, four, five), label: "rendezvous: keys moved")

# On a real cluster the node list comes from
# `Node.list/0` or a `:pg` group, and a request for a
# key is sent to its owner:
#
#     owner = Ring.owner(ring, key)
#     :erpc.call(owner, KV, :get, [key])
#
# The script above uses plain atoms for nodes so it can
# run anywhere, including the browser.
#
# > **Pitfall:** a key that moves needs its data moved
# > too. Until the new owner has it, reads there miss.
# > Copy the data over before routing to the new node,
# > or read from the old owner as a fallback (see
# > [Catching up new nodes](/distributed/kv-09-catching-up)).
#
# > **Pitfall:** nodes only agree on owners while they
# > agree on the node list. During a partition, each
# > side computes owners from the nodes it can see, and
# > the same key has two owners (see
# > [Partitions and Split Brain](/distributed/partitions)).
#
# > **Pitfall:** the hash is of the *term*, so `42`,
# > `"42"` and `:"42"` are three different keys with
# > three different owners. Normalize keys (one type,
# > one case) before hashing them.
