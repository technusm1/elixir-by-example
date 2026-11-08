# KV now serves many clients, and one of them is a
# script stuck in a loop, writing as fast as it can. It
# isn't malicious, just broken, and every write it makes
# is time the store doesn't spend on everyone else.
#
# This step puts a limit on each client: at most `limit`
# writes per second. The counts live in an ETS table
# with `:ets.update_counter/4`, as on
# [Rate Limiting](/otp/rate-limiting), so checking the
# limit never waits on a process. Writes that pass go to
# the store; writes over the limit get
# `{:error, :rate_limited}` at once.
#
# The store is step 6's: a GenServer owns the table and
# serializes writes, and reads go straight to ETS.
# Reads aren't limited here: they're cheap, and they
# don't queue behind anything.
defmodule KV.Store do
  use GenServer

  @table __MODULE__

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  def put(key, value), do: GenServer.call(__MODULE__, {:put, key, value})

  def get(key) do
    case :ets.lookup(@table, key) do
      [{^key, value}] -> {:ok, value}
      [] -> :error
    end
  end

  @impl true
  def init(nil) do
    :ets.new(@table, [:set, :protected, :named_table, read_concurrency: true])
    {:ok, nil}
  end

  @impl true
  def handle_call({:put, key, value}, _from, state) do
    :ets.insert(@table, {key, value})
    {:reply, :ok, state}
  end
end

# The limiter: a fixed window per client. The clock is
# passed in, so the demo controls time.
defmodule KV.Limiter do
  @table __MODULE__

  def start, do: :ets.new(@table, [:set, :public, :named_table, write_concurrency: true])

  def check(client, limit, now) do
    slot = {client, div(now, 1_000)}
    count = :ets.update_counter(@table, slot, {2, 1}, {slot, 0})
    if count <= limit, do: :ok, else: {:error, :rate_limited}
  end

  # Old windows are useless once the clock has moved
  # past them.
  def sweep(now) do
    current = div(now, 1_000)
    :ets.select_delete(@table, [{{{:_, :"$1"}, :_}, [{:<, :"$1", current}], [true]}])
  end
end

# The API clients use: check the limit, then write.
# Reads aren't limited: `defdelegate` defines `get/1`
# as a plain call to `KV.Store.get/1`.
defmodule KV do
  @limit 5

  def put(client, key, value, now) do
    with :ok <- KV.Limiter.check(client, @limit, now) do
      KV.Store.put(key, value)
    end
  end

  defdelegate get(key), to: KV.Store
end

{:ok, _} = KV.Store.start_link(nil)
KV.Limiter.start()

# In the same second, the broken script sends 20 writes
# and a well-behaved client sends 2. The script gets 5
# through; the other client isn't affected at all.
loop = for n <- 1..20, do: KV.put(:loop_script, "counter", n, 10_000)
IO.inspect(Enum.frequencies(loop), label: "loop script")

fine = for n <- 1..2, do: KV.put(:billing, "invoice:#{n}", :paid, 10_000)
IO.inspect(fine, label: "billing")

# The store has the loop script's fifth write, the last
# one let through.
IO.inspect(KV.get("counter"), label: "counter")

# A second later, a new window: the script gets its next
# five.
again = for n <- 21..30, do: KV.put(:loop_script, "counter", n, 11_000)
IO.inspect(Enum.frequencies(again), label: "loop script, next second")

# The sweep deletes the windows that are over.
IO.inspect(KV.Limiter.sweep(11_000), label: "old windows deleted")

# Limiting stops one client from hogging the store. It
# doesn't help when *every* client is fine and the
# store is still too slow, for example because each
# write must reach a slow disk. That's the next step:
# backpressure.
