# Step 6's keys never went away. A cache needs a TTL.
# Each row now stores an expiry time. Reads ignore
# expired rows right away, and a periodic sweep
# (a message the GenServer sends itself) deletes them
# so memory doesn't grow forever.
defmodule KV.Cache do
  use GenServer

  @table __MODULE__

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def put(key, value, ttl_ms), do: GenServer.call(__MODULE__, {:put, key, value, ttl_ms})

  # Reads check the expiry themselves, so a key is
  # invisible the moment it expires, not whenever the
  # next sweep happens to run.
  def get(key) do
    now = now()

    case :ets.lookup(@table, key) do
      [{^key, value, expires}] when expires > now -> {:ok, value}
      _ -> :error
    end
  end

  def size, do: :ets.info(@table, :size)

  # Sweep on demand, so we can show it without
  # waiting for the timer.
  def sweep, do: GenServer.call(__MODULE__, :sweep)

  defp now, do: System.monotonic_time(:millisecond)

  @impl true
  def init(opts) do
    :ets.new(@table, [:set, :protected, :named_table, read_concurrency: true])
    interval = Keyword.get(opts, :sweep_every, 1_000)
    Process.send_after(self(), :sweep, interval)
    {:ok, %{interval: interval}}
  end

  @impl true
  def handle_call({:put, k, v, ttl}, _from, s) do
    :ets.insert(@table, {k, v, now() + ttl})
    {:reply, :ok, s}
  end

  def handle_call(:sweep, _from, s), do: {:reply, delete_expired(), s}

  # The timer message arrives in `handle_info`. We
  # re-arm it every time, so it keeps running.
  @impl true
  def handle_info(:sweep, s) do
    delete_expired()
    Process.send_after(self(), :sweep, s.interval)
    {:noreply, s}
  end

  # `select_delete` removes every row whose expiry is
  # in the past, inside ETS, without copying rows out.
  defp delete_expired do
    :ets.select_delete(@table, [{{:_, :_, :"$1"}, [{:"=<", :"$1", now()}], [true]}])
  end
end

# Monotonic time is used deliberately: wall-clock time
# can jump (NTP, daylight saving), monotonic can't.
{:ok, _} = KV.Cache.start_link(sweep_every: 60_000)

KV.Cache.put("session:ada", :token_a, 50)
KV.Cache.put("session:grace", :token_g, 60_000)

IO.inspect(KV.Cache.get("session:ada"), label: "ada right away")
Process.sleep(100)
IO.inspect(KV.Cache.get("session:ada"), label: "ada after 100 ms")
IO.inspect(KV.Cache.size(), label: "rows before sweep")
IO.inspect(KV.Cache.sweep(), label: "swept")
IO.inspect(KV.Cache.get("session:grace"), label: "grace")

# KV is now concurrent, supervised, fast to read and
# self-cleaning, but it lives on one machine. If that
# node dies, everything is gone. The Distributed track
# picks up here: connecting nodes, replicating buckets
# with `:pg` process groups, and persisting with
# Mnesia.
