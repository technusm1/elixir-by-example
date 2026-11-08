# A *read-through* cache answers from memory when it
# can, and on a miss loads the value from the slow
# source (a database, an API), stores it and returns
# it. On the BEAM the memory is an ETS table: any
# process can read it directly, with no process in the
# way.
#
# The obvious version has a problem. When a popular key
# is missing (it expired, or the node just started),
# every request that arrives before the first load
# finishes also misses, and they *all* load it. That's
# a *cache stampede*, and it hits the slow source at the
# worst possible moment.
defmodule NaiveCache do
  def new, do: :ets.new(:naive, [:set, :public])

  def fetch(table, key, loader) do
    case :ets.lookup(table, key) do
      [{^key, value}] ->
        {:ok, value}

      [] ->
        with {:ok, value} <- loader.() do
          :ets.insert(table, {key, value})
          {:ok, value}
        end
    end
  end
end

# A loader that takes 50 ms and counts its calls in a
# `:counters` array, which any process can bump.
loads = :counters.new(1, [])

loader = fn ->
  :counters.add(loads, 1, 1)
  Process.sleep(50)
  {:ok, "profile 42"}
end

# Fifty processes ask for the same key at once. They
# wait for a `:go` message first, so they really do
# start together.
stampede = fn label, fetch ->
  :counters.put(loads, 1, 0)
  tasks = for _ <- 1..50, do: Task.async(fn -> receive(do: (:go -> fetch.())) end)
  for task <- tasks, do: send(task.pid, :go)
  [answer] = tasks |> Task.await_many() |> Enum.uniq()
  IO.puts("#{label}: all 50 got #{inspect(answer)}, loads: #{:counters.get(loads, 1)}")
end

table = NaiveCache.new()
stampede.("naive", fn -> NaiveCache.fetch(table, :user_42, loader) end)

# The fix is *single-flight* loading: the first miss
# loads the key, and later misses for the same key wait
# for that load instead of starting their own. A
# GenServer coordinates the misses. It owns the table,
# keeps a list of callers waiting for each key, and
# answers them all with deferred replies when the load
# finishes. Hits still read ETS directly and never touch
# the process.
defmodule Cache do
  use GenServer

  def start_link(name), do: GenServer.start_link(__MODULE__, name, name: name)

  def fetch(cache, key, loader) do
    case :ets.lookup(cache, key) do
      [{^key, value}] -> {:ok, value}
      [] -> GenServer.call(cache, {:load, key, loader}, :infinity)
    end
  end

  def invalidate(cache, key), do: GenServer.call(cache, {:invalidate, key})

  @impl true
  def init(name) do
    # Named after the server, so `fetch/3` can read it
    # by name. `:protected`: everyone reads, only the
    # owner writes.
    :ets.new(name, [:set, :protected, :named_table, read_concurrency: true])
    {:ok, %{table: name, waiting: %{}, loads: %{}}}
  end

  @impl true
  def handle_call({:load, key, loader}, from, state) do
    cond do
      # Loaded while this caller was on its way here.
      match?([_], :ets.lookup(state.table, key)) ->
        [{^key, value}] = :ets.lookup(state.table, key)
        {:reply, {:ok, value}, state}

      # Already loading: join the waiters.
      Map.has_key?(state.waiting, key) ->
        {:noreply, update_in(state.waiting[key], &[from | &1])}

      # First miss: start the one load.
      true ->
        task = Task.async(loader)

        {:noreply,
         %{
           state
           | waiting: Map.put(state.waiting, key, [from]),
             loads: Map.put(state.loads, task.ref, key)
         }}
    end
  end

  def handle_call({:invalidate, key}, _from, state) do
    :ets.delete(state.table, key)
    {:reply, :ok, state}
  end

  @impl true
  def handle_info({ref, result}, state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    {key, loads} = Map.pop!(state.loads, ref)
    {waiters, waiting} = Map.pop!(state.waiting, key)

    # Only successes are cached. A failed load is
    # returned to everyone who waited, and the next
    # request tries again.
    with {:ok, value} <- result, do: :ets.insert(state.table, {key, value})
    for from <- waiters, do: GenServer.reply(from, result)

    {:noreply, %{state | waiting: waiting, loads: loads}}
  end
end

{:ok, _} = Cache.start_link(Profiles)
stampede.("single-flight", fn -> Cache.fetch(Profiles, :user_42, loader) end)

# Now the key is cached, so the same stampede doesn't
# load at all.
stampede.("cached", fn -> Cache.fetch(Profiles, :user_42, loader) end)

# A failed load isn't cached: every waiter gets the
# error, and the next request loads again.
failing = fn ->
  :counters.add(loads, 1, 1)
  Process.sleep(50)
  {:error, :db_timeout}
end

stampede.("failing", fn -> Cache.fetch(Profiles, :user_7, failing) end)
IO.inspect(Cache.fetch(Profiles, :user_7, loader), label: "next request")

# > **Pitfall:** "there are only two hard things in
# > computer science: cache invalidation and naming
# > things." When the source changes, the cache has to
# > hear about it (`Cache.invalidate/2` after every
# > write), or entries need a time to live (see
# > [Expiring keys](/otp/kv-07-expiring-keys)). Without
# > one of those, the cache serves stale data forever.
#
# > **Pitfall:** invalidating while a load is in flight
# > can still cache the old value: the load started
# > before the write, and it finishes after the delete.
# > If that matters, version the entries, or have the
# > writer put the new value in the cache itself.
#
# > **Pitfall:** `Task.async/1` links the loader to the
# > cache, so a loader that *raises* takes the cache
# > down. Loaders here return `{:error, reason}`; to
# > survive crashes, start them with
# > `Task.Supervisor.async_nolink/2` and handle the
# > `:DOWN` as in [Job Queue](/otp/job-queue).
