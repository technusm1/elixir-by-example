# ETS (Erlang Term Storage) is an in-memory table
# built into the VM. Any process can read it without
# sending a message, which makes it the standard tool
# for hot, shared, read-heavy data like caches.
table = :ets.new(:cache, [:set, :public, read_concurrency: true])

# Rows are tuples; the first element is the key.
:ets.insert(table, {"ada", :admin})
:ets.insert(table, {"grace", :editor})
:ets.insert(table, {"ada", :owner})

# `:set` keeps one row per key, so the second insert
# for "ada" replaced the first.
IO.inspect(:ets.lookup(table, "ada"), label: "lookup ada")
IO.inspect(:ets.lookup(table, "joe"), label: "lookup joe")

# Counters are atomic, even with many writers.
:ets.insert(table, {:hits, 0})

1..100
|> Enum.map(fn _ -> Task.async(fn -> :ets.update_counter(table, :hits, 1) end) end)
|> Task.await_many()

IO.inspect(:ets.lookup_element(table, :hits, 2), label: "hits")

# `:ordered_set` keeps keys sorted, so you can walk
# ranges. `:bag` allows several rows per key.
scores = :ets.new(:scores, [:ordered_set])
for {name, score} <- [{"c", 30}, {"a", 10}, {"b", 20}], do: :ets.insert(scores, {name, score})
IO.inspect(:ets.tab2list(scores), label: "ordered_set")

tags = :ets.new(:tags, [:bag])
:ets.insert(tags, [{"post1", "elixir"}, {"post1", "otp"}, {"post2", "elixir"}])
IO.inspect(:ets.lookup(tags, "post1"), label: "bag")

# `match_object` and `select` query by pattern. `:_`
# matches anything. Select uses match specs; build
# them with `:ets.fun2ms/1` in IEx when they get hairy.
IO.inspect(:ets.match_object(tags, {:_, "elixir"}), label: "tagged elixir")

high = :ets.select(scores, [{{:"$1", :"$2"}, [{:>, :"$2", 15}], [:"$1"]}])
IO.inspect(high, label: "score > 15")

# Every table has an *owner*: the process that
# created it. When the owner dies, the table is
# deleted, whatever other processes think.
parent = self()

owner =
  spawn(fn ->
    t = :ets.new(:short_lived, [:public])
    :ets.insert(t, {"answer", 42})
    send(parent, {:table, t})
    receive do: (:stop -> :ok)
  end)

t =
  receive do
    {:table, t} -> t
  end

IO.inspect(:ets.lookup(t, "answer"), label: "while owner lives")
ref = Process.monitor(owner)
send(owner, :stop)
receive do: ({:DOWN, ^ref, _, _, _} -> :ok)
IO.inspect(:ets.info(t), label: "after owner died")

# > **Pitfall:** creating an ETS table from a
# > short-lived process (a Task, a request handler)
# > means it vanishes when that process ends. Create
# > long-lived tables in a supervised GenServer that
# > lives as long as the data should.
#
# > **Pitfall:** ETS is not a transaction store.
# > `lookup` then `insert` from two processes is a race.
# > Use `update_counter`, `insert_new`, or route writes
# > through one GenServer and let readers hit the table.
