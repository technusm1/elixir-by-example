# Reads in step 5 went through a process mailbox, so
# a slow write delayed every reader. Most stores read
# far more than they write. Here, writes still go
# through one GenServer (so they're ordered), but reads
# go straight to a `:protected` ETS table: every
# process can read it, only the owner can write.
defmodule KV.Cache do
  use GenServer

  @table __MODULE__

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  # Reads: no message, no waiting on the GenServer.
  # Rows are `{{bucket, key}, value}`.
  def get(bucket, key) do
    case :ets.lookup(@table, {bucket, key}) do
      [{_, value}] -> {:ok, value}
      [] -> :error
    end
  end

  # Writes: serialized through the owner process.
  def put(bucket, key, value), do: GenServer.call(__MODULE__, {:put, bucket, key, value})

  # A bucket's keys, using a match on the first half of
  # the composite key. `:ets.match/2` returns, for each
  # matching row, a list of what the `:"$1"` slots
  # matched; `:_` matches anything.
  def keys(bucket) do
    @table |> :ets.match({{bucket, :"$1"}, :_}) |> List.flatten() |> Enum.sort()
  end

  @impl true
  def init(nil) do
    # A *named* table, readable by everyone, tuned for
    # many concurrent readers.
    :ets.new(@table, [:set, :protected, :named_table, read_concurrency: true])
    {:ok, nil}
  end

  @impl true
  def handle_call({:put, b, k, v}, _from, state) do
    :ets.insert(@table, {{b, k}, v})
    {:reply, :ok, state}
  end
end

{:ok, _} = KV.Cache.start_link([])

KV.Cache.put("users", "ada", :admin)
KV.Cache.put("users", "grace", :editor)
KV.Cache.put("flags", "dark_mode", true)

IO.inspect(KV.Cache.get("users", "ada"), label: "get")
IO.inspect(KV.Cache.get("users", "joe"), label: "missing")
IO.inspect(KV.Cache.keys("users"), label: "users keys")

# 1,000 concurrent readers, and the GenServer never
# sees a single one of their requests.
hits =
  1..1_000
  |> Task.async_stream(fn _ -> KV.Cache.get("flags", "dark_mode") end, max_concurrency: 50)
  |> Enum.count(fn {:ok, result} -> result == {:ok, true} end)

IO.inspect(hits, label: "successful parallel reads")

# `:protected` means writes from other processes fail.
# That's what keeps all writes ordered through the
# GenServer.
try do
  :ets.insert(KV.Cache, {{"users", "mallory"}, :admin})
rescue
  ArgumentError -> IO.puts("direct write from outside the owner: rejected")
end

# Keys live forever, though, and caches need to forget.
# Step 7 adds expiry.
