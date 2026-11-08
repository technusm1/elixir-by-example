# A rate limiter caps how often something may happen:
# requests per client, calls to a paid API, login
# attempts. The usual algorithm is a *token bucket*.
# The bucket holds up to `capacity` tokens and gains one
# every `interval` milliseconds. Each request takes a
# token, and with no token left it's refused. A full
# bucket allows a short burst, then the rate settles to
# one request per interval.
#
# The bucket itself is plain data. It takes the current
# time as an argument instead of reading a clock, so it
# is easy to test and the output below doesn't depend on
# how fast the machine is.
defmodule TokenBucket do
  defstruct [:capacity, :interval, :tokens, :last]

  def new(capacity, interval, now) do
    %TokenBucket{capacity: capacity, interval: interval, tokens: capacity, last: now}
  end

  def take(bucket, now) do
    bucket = refill(bucket, now)

    if bucket.tokens > 0 do
      {:ok, %{bucket | tokens: bucket.tokens - 1}}
    else
      {:error, {:retry_in, bucket.interval - (now - bucket.last)}, bucket}
    end
  end

  # Whole intervals since `last` become tokens. `last`
  # only moves by whole intervals, so time that hasn't
  # yet earned a token isn't thrown away.
  defp refill(bucket, now) do
    earned = div(now - bucket.last, bucket.interval)

    if bucket.tokens + earned >= bucket.capacity do
      %{bucket | tokens: bucket.capacity, last: now}
    else
      %{bucket | tokens: bucket.tokens + earned, last: bucket.last + earned * bucket.interval}
    end
  end
end

# Three tokens, one more every 200 ms. Four requests at
# the same moment: the burst of three goes through, the
# fourth is told when to come back.
bucket = TokenBucket.new(3, 200, 0)

bucket =
  Enum.reduce(1..4, bucket, fn n, bucket ->
    case TokenBucket.take(bucket, 0) do
      {:ok, bucket} ->
        IO.puts("t=0    request #{n}: ok")
        bucket

      {:error, {:retry_in, ms}, bucket} ->
        IO.puts("t=0    request #{n}: refused, retry in #{ms} ms")
        bucket
    end
  end)

# 150 ms later there's still no token; at 200 ms there
# is exactly one.
{:error, {:retry_in, ms}, bucket} = TokenBucket.take(bucket, 150)
IO.puts("t=150  refused, retry in #{ms} ms")
{:ok, bucket} = TokenBucket.take(bucket, 200)
IO.puts("t=200  ok")
{:error, _, _} = TokenBucket.take(bucket, 200)
IO.puts("t=200  refused again")

# To share limits across a whole program, put one bucket
# per key (a client, a user id) in a GenServer. The clock
# is a function, passed in when the server starts: the
# real one by default, a fake one in this demo. The
# real one is monotonic time, which only moves forward;
# the wall clock can jump when the system time is
# adjusted. `put_in(state.buckets[key], bucket)` sets
# the value at that path inside the state.
defmodule Limiter do
  use GenServer

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)
  def allow(limiter, key), do: GenServer.call(limiter, {:allow, key})

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    {:ok, %{opts: opts, clock: clock, buckets: %{}}}
  end

  @impl true
  def handle_call({:allow, key}, _from, state) do
    now = state.clock.()

    bucket =
      Map.get_lazy(state.buckets, key, fn ->
        TokenBucket.new(state.opts[:capacity], state.opts[:interval], now)
      end)

    case TokenBucket.take(bucket, now) do
      {:ok, bucket} -> {:reply, :ok, put_in(state.buckets[key], bucket)}
      {:error, reason, bucket} -> {:reply, {:error, reason}, put_in(state.buckets[key], bucket)}
    end
  end
end

{:ok, clock} = Agent.start_link(fn -> 0 end)
fake_clock = fn -> Agent.get(clock, & &1) end
{:ok, limiter} = Limiter.start_link(capacity: 2, interval: 1_000, clock: fake_clock)

# Each key has its own bucket, so one busy client
# doesn't use up anyone else's allowance.
results = for key <- [:alice, :alice, :alice, :bob], do: {key, Limiter.allow(limiter, key)}
IO.inspect(results, label: "at t=0")

Agent.update(clock, fn _ -> 1_000 end)
IO.inspect(Limiter.allow(limiter, :alice), label: "alice at t=1000")

# Every request in the system now goes through one
# process. That's fine for many workloads, but it is a
# bottleneck by design (see [GenServer](/otp/genserver)).
#
# For a hot path, keep the counts in ETS instead.
# `:ets.update_counter/4` increments atomically, so
# concurrent callers never need a process in between.
# Here `{2, 1}` adds 1 to the row's second element,
# and `{slot, 0}` is the row to insert first when the
# key is missing.
# This version uses a *fixed window*: at most `limit`
# requests per key in each window of `window` ms. The
# window's number is part of the key.
defmodule WindowLimiter do
  def new, do: :ets.new(:windows, [:set, :public, write_concurrency: true])

  def allow(table, key, limit, window, now) do
    slot = {key, div(now, window)}
    count = :ets.update_counter(table, slot, {2, 1}, {slot, 0})
    if count <= limit, do: :ok, else: {:error, :rate_limited}
  end
end

# A hundred processes hit a limit of ten at the same
# moment. Exactly ten get through: the increment and the
# read happen as one atomic step, so no two callers can
# see the same count.
table = WindowLimiter.new()

allowed =
  1..100
  |> Task.async_stream(fn _ -> WindowLimiter.allow(table, :api, 10, 1_000, 5_000) end,
    max_concurrency: 100
  )
  |> Enum.count(&(&1 == {:ok, :ok}))

IO.inspect(allowed, label: "allowed out of 100")

# > **Pitfall:** a fixed window lets through up to *twice*
# > the limit around a window boundary: a full window's
# > worth just before the edge and another just after.
# > Here ten requests within 2 ms are all allowed
# > under a limit of five per second. A token
# > bucket, or a *sliding* window that also counts part
# > of the previous window, doesn't have this gap.
table = WindowLimiter.new()
before = for _ <- 1..5, do: WindowLimiter.allow(table, :api, 5, 1_000, 999)
later = for _ <- 1..5, do: WindowLimiter.allow(table, :api, 5, 1_000, 1_001)
IO.inspect(Enum.count(before ++ later, &(&1 == :ok)), label: "allowed between t=999 and t=1001")

# > **Pitfall:** old windows stay in the table forever.
# > Delete them from time to time, for example with
# > `:ets.select_delete/2` from a process that ticks
# > once per window.
#
# > **Pitfall:** limits kept in one node's memory are per
# > node. Behind a load balancer with four nodes, "10
# > per second" quietly becomes 40. Either route each
# > key to one node (see [Sharding](/distributed/sharding)),
# > or keep the counts in a shared store.
