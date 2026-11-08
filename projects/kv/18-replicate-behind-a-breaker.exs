# KV copies every write to a replica on another node.
# When that node is down, Erlang notices quickly and the
# call fails at once. When it *hangs* (a long garbage
# collection, a stuck disk, a network that drops packets
# silently) the call waits for its whole timeout. Then
# every `put` on the primary is slow, because of a
# replica nobody is even reading from.
#
# This step puts the replication behind the circuit
# breaker from [Circuit Breaker](/otp/circuit-breaker).
# After three timeouts the breaker opens, and writes
# stop waiting for the replica. The keys it missed are
# remembered, and once a trial write gets through, the
# primary sends the replica their current values.
#
# To keep this runnable anywhere, the "remote" replica
# is a local process, and a hang is simulated with
# `:sys.suspend/1`: the process stops handling
# messages, exactly what a hung node looks like from the
# outside.
defmodule Breaker do
  @behaviour :gen_statem

  def start_link(opts), do: :gen_statem.start_link({:local, opts[:name]}, __MODULE__, opts, [])
  def state(breaker), do: :gen_statem.call(breaker, :state)

  def run(breaker, fun) do
    case :gen_statem.call(breaker, :ask) do
      :go ->
        result = fun.()
        :gen_statem.cast(breaker, {:report, result})
        result

      :reject ->
        {:error, :circuit_open}
    end
  end

  @impl true
  def callback_mode, do: [:handle_event_function, :state_enter]

  @impl true
  def init(opts), do: {:ok, :closed, %{failures: 0, opts: opts, trial: false}}

  # Enter calls set each state up: open starts the
  # cooldown, closed and half-open clear the counters.
  @impl true
  def handle_event(:enter, _, :open, data),
    do: {:keep_state_and_data, [{:state_timeout, data.opts[:cooldown], :retry}]}

  def handle_event(:enter, _, _, data), do: {:keep_state, %{data | failures: 0, trial: false}}

  def handle_event({:call, from}, :state, state, _),
    do: {:keep_state_and_data, [{:reply, from, state}]}

  def handle_event({:call, from}, :ask, :closed, _),
    do: {:keep_state_and_data, [{:reply, from, :go}]}

  def handle_event({:call, from}, :ask, :open, _),
    do: {:keep_state_and_data, [{:reply, from, :reject}]}

  def handle_event({:call, from}, :ask, :half_open, %{trial: false} = data),
    do: {:keep_state, %{data | trial: true}, [{:reply, from, :go}]}

  def handle_event({:call, from}, :ask, :half_open, _),
    do: {:keep_state_and_data, [{:reply, from, :reject}]}

  def handle_event(:cast, {:report, {:ok, _}}, :closed, data),
    do: {:keep_state, %{data | failures: 0}}

  def handle_event(:cast, {:report, {:ok, _}}, :half_open, data), do: {:next_state, :closed, data}

  def handle_event(:cast, {:report, {:error, _}}, :closed, data) do
    if data.failures + 1 >= data.opts[:threshold],
      do: {:next_state, :open, data},
      else: {:keep_state, %{data | failures: data.failures + 1}}
  end

  def handle_event(:cast, {:report, {:error, _}}, :half_open, data),
    do: {:next_state, :open, data}

  def handle_event(:cast, {:report, _}, :open, _), do: :keep_state_and_data
  def handle_event(:state_timeout, :retry, :open, data), do: {:next_state, :half_open, data}
end

# The replica: a map in a GenServer. Calls to it time
# out after 50 ms.
defmodule KV.Replica do
  use GenServer

  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  def dump, do: GenServer.call(__MODULE__, :dump)

  def put(key, value) do
    {:ok, GenServer.call(__MODULE__, {:put, key, value}, 50)}
  catch
    :exit, {:timeout, _} -> {:error, :timeout}
  end

  @impl true
  def init(map), do: {:ok, map}

  @impl true
  def handle_call({:put, key, value}, _from, map), do: {:reply, :ok, Map.put(map, key, value)}
  def handle_call(:dump, _from, map), do: {:reply, map, map}
end

# The primary: an ETS table for the data and another
# for the keys the replica missed.
defmodule KV do
  def start do
    :ets.new(:kv, [:set, :public, :named_table])
    :ets.new(:kv_missed, [:set, :public, :named_table])
  end

  def put(key, value) do
    :ets.insert(:kv, {key, value})

    case Breaker.run(KV.Breaker, fn -> KV.Replica.put(key, value) end) do
      {:ok, :ok} ->
        catch_up()
        :replicated

      {:error, reason} ->
        :ets.insert(:kv_missed, {key})
        reason
    end
  end

  # Send the replica the *current* value of every missed
  # key. Writing a key's latest value again is harmless,
  # so this can safely repeat.
  def catch_up do
    for {key} <- :ets.tab2list(:kv_missed) do
      [{^key, value}] = :ets.lookup(:kv, key)
      {:ok, :ok} = KV.Replica.put(key, value)
      :ets.delete(:kv_missed, key)
    end
  end

  def dump, do: Map.new(:ets.tab2list(:kv))
end

defmodule Wait do
  def until(check) do
    if check.(), do: :ok, else: Process.sleep(1) && until(check)
  end
end

KV.start()
{:ok, _} = KV.Replica.start_link(nil)
{:ok, _} = Breaker.start_link(name: KV.Breaker, threshold: 3, cooldown: 100)

IO.inspect(KV.put("a", 1), label: "put a")

# The replica hangs. The first three writes each wait
# the full 50 ms and time out; then the breaker opens,
# and the next writes don't wait at all.
:sys.suspend(KV.Replica)

for key <- ["b", "c", "d", "e", "f"] do
  IO.inspect(KV.put(key, 2), label: "put #{key}")
end

IO.inspect(Breaker.state(KV.Breaker), label: "breaker")

# The replica recovers. While it was hung, the three
# timed-out calls stayed in its mailbox; it handles them
# now, and nobody is waiting for the replies any more.
:sys.resume(KV.Replica)

# After the cooldown, the next write is the trial. It
# gets through, the breaker closes, and the primary
# replays every missed key.
Wait.until(fn -> Breaker.state(KV.Breaker) == :half_open end)
IO.inspect(KV.put("g", 3), label: "put g")
IO.inspect(Breaker.state(KV.Breaker), label: "breaker")
IO.inspect(KV.Replica.dump() == KV.dump(), label: "replica matches primary")
IO.inspect(KV.Replica.dump(), label: "replica")

# KV now limits greedy clients, bounds its memory under
# a burst of writes, and keeps working when its replica
# doesn't. What it doesn't do yet is remember the missed
# keys across a restart of the primary: `:kv_missed`
# is in memory. Storing it next to the data, in the
# same write (the idea behind
# [the outbox](/reliability/outbox)), closes that gap.
