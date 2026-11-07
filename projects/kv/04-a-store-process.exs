# Steps 1-3 built a store that lives in a variable. To
# share it between processes it has to live *in* a
# process. A GenServer holds the buckets as its state,
# and every caller talks to it by name.
#
# The pure data code doesn't change. The GenServer is
# a thin shell around it, which keeps the logic easy
# to test without processes.
defmodule KV.Data do
  def put(b, bucket, key, value),
    do: Map.update(b, bucket, %{key => value}, &Map.put(&1, key, value))

  def get(b, bucket, key), do: b |> Map.get(bucket, %{}) |> Map.fetch(key)
  def delete(b, bucket, key), do: Map.update(b, bucket, %{}, &Map.delete(&1, key))
end

defmodule KV.Server do
  use GenServer

  def start_link(opts), do: GenServer.start_link(__MODULE__, %{}, name: opts[:name] || __MODULE__)

  # Writes are calls too: the caller learns the write
  # happened before it continues, so a read right after
  # a write always sees it.
  def put(bucket, key, value), do: GenServer.call(__MODULE__, {:put, bucket, key, value})
  def get(bucket, key), do: GenServer.call(__MODULE__, {:get, bucket, key})
  def delete(bucket, key), do: GenServer.call(__MODULE__, {:delete, bucket, key})

  @impl true
  def init(buckets), do: {:ok, buckets}

  @impl true
  def handle_call({:put, b, k, v}, _from, s), do: {:reply, :ok, KV.Data.put(s, b, k, v)}
  def handle_call({:get, b, k}, _from, s), do: {:reply, KV.Data.get(s, b, k), s}
  def handle_call({:delete, b, k}, _from, s), do: {:reply, :ok, KV.Data.delete(s, b, k)}
end

{:ok, _} = KV.Server.start_link([])

KV.Server.put("users", "ada", :admin)
IO.inspect(KV.Server.get("users", "ada"), label: "get")

# Now many processes share one store. 50 tasks write
# concurrently; the GenServer applies them one at a
# time, so none are lost.
1..50
|> Enum.map(fn i -> Task.async(fn -> KV.Server.put("counters", "k#{i}", i) end) end)
|> Task.await_many()

{:ok, 50} = KV.Server.get("counters", "k50")
IO.inspect(KV.Server.get("counters", "k7"), label: "written by another process")

KV.Server.delete("users", "ada")
IO.inspect(KV.Server.get("users", "ada"), label: "after delete")

# Two problems remain. One crash in any bucket takes
# the whole store down, and one busy bucket slows down
# all the others because a single process serves
# everything. Step 5 gives each bucket its own
# supervised process.
