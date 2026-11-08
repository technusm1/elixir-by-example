# KV keeps a log of every write on disk, so it can
# rebuild its table after a restart. The disk is slow:
# each write takes 10 ms. Making every `put` wait for
# the disk would make every client that slow.
#
# So this step uses *write-behind*. A `put` updates the
# table (readers see the new value at once) and goes
# into a buffer. A separate disk process writes the
# buffer out, one entry at a time, and `put` returns as
# soon as its write is in the buffer.
#
# Unbounded, that buffer is a time bomb: a burst of
# writes faster than the disk piles up in memory. So it
# has a capacity, and when it's full, `put` simply
# doesn't reply yet. That's the deferred reply from
# [Backpressure](/otp/backpressure): writers wait,
# memory stays bounded, and writers speed back up as
# soon as the disk catches up.
defmodule KV.Disk do
  # The slow disk: an Agent holding the log. Each write
  # takes 10 ms, then tells the store it's done.
  def start, do: Agent.start_link(fn -> [] end, name: __MODULE__)

  def write(store, entry) do
    Agent.cast(__MODULE__, fn log ->
      Process.sleep(10)
      send(store, :written)
      [entry | log]
    end)
  end

  def log, do: Agent.get(__MODULE__, &Enum.reverse/1)
end

defmodule KV.Store do
  use GenServer

  @table __MODULE__

  def start_link(capacity), do: GenServer.start_link(__MODULE__, capacity, name: __MODULE__)

  def put(key, value), do: GenServer.call(__MODULE__, {:put, key, value}, :infinity)

  def get(key) do
    case :ets.lookup(@table, key) do
      [{^key, value}] -> {:ok, value}
      [] -> :error
    end
  end

  # Waits (deferred reply again) until everything
  # buffered is on disk.
  def flush, do: GenServer.call(__MODULE__, :flush, :infinity)
  def stats, do: GenServer.call(__MODULE__, :stats)

  @impl true
  def init(capacity) do
    :ets.new(@table, [:set, :protected, :named_table, read_concurrency: true])

    {:ok,
     %{
       capacity: capacity,
       buffer: :queue.new(),
       waiting: :queue.new(),
       writing: false,
       longest: 0,
       flushers: []
     }}
  end

  @impl true
  def handle_call({:put, key, value}, from, state) do
    :ets.insert(@table, {key, value})

    if :queue.len(state.buffer) < state.capacity do
      state = %{state | buffer: :queue.in({key, value}, state.buffer)}
      {:reply, :ok, state |> track() |> write_next()}
    else
      {:noreply, %{state | waiting: :queue.in({from, {key, value}}, state.waiting)}}
    end
  end

  def handle_call(:flush, from, state) do
    {:noreply, maybe_flushed(%{state | flushers: [from | state.flushers]})}
  end

  def handle_call(:stats, _from, state) do
    {:reply, %{longest_buffer: state.longest, capacity: state.capacity}, state}
  end

  # The disk finished an entry: drop it from the buffer,
  # let one waiting writer in, and start the next write.
  @impl true
  def handle_info(:written, state) do
    {_, buffer} = :queue.out(state.buffer)

    state =
      case :queue.out(state.waiting) do
        {{:value, {from, entry}}, waiting} ->
          GenServer.reply(from, :ok)
          %{state | buffer: :queue.in(entry, buffer), waiting: waiting}

        {:empty, _} ->
          %{state | buffer: buffer}
      end

    {:noreply, %{state | writing: false} |> track() |> write_next() |> maybe_flushed()}
  end

  # The entry being written stays at the head of the
  # buffer until the disk confirms it.
  defp write_next(%{writing: false} = state) do
    case :queue.peek(state.buffer) do
      {:value, entry} ->
        KV.Disk.write(self(), entry)
        %{state | writing: true}

      :empty ->
        state
    end
  end

  defp write_next(state), do: state

  defp track(state), do: %{state | longest: max(state.longest, :queue.len(state.buffer))}

  defp maybe_flushed(state) do
    if :queue.is_empty(state.buffer) and state.flushers != [] do
      for from <- state.flushers, do: GenServer.reply(from, :ok)
      %{state | flushers: []}
    else
      state
    end
  end
end

{:ok, _} = KV.Disk.start()
{:ok, _} = KV.Store.start_link(3)

# A burst: 12 clients write at once. The disk needs
# 120 ms for all of them, but the buffer never holds
# more than 3; the other writers wait their turn inside
# `put`.
writers = for n <- 1..12, do: Task.async(fn -> KV.Store.put("order:#{n}", :placed) end)
IO.inspect(Task.await_many(writers) |> Enum.uniq(), label: "every put returned")
IO.inspect(KV.Store.stats(), label: "stats")

# Reads never waited for the disk.
IO.inspect(KV.Store.get("order:12"), label: "read order:12")

# Once the buffer is flushed, all 12 writes are in the
# log, each exactly once.
:ok = KV.Store.flush()
log = KV.Disk.log()
IO.inspect({length(log), length(Enum.uniq(log))}, label: "log entries, unique")

# Write-behind has a price: a `put` that returned `:ok`
# may still be in the buffer. If the node dies now,
# those writes are lost. A store that must never lose an
# acknowledged write replies only after the disk has it
# (and lives with the slower writes), or replicates
# them, which is the next step.
