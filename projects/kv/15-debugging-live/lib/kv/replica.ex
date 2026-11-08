defmodule KV.Replica do
  @moduledoc "One replica of the store; every write goes to all of them (step 8)."
  use GenServer

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def put(key, value) do
    for replica <- :pg.get_members(:kv_replicas) do
      :ok = GenServer.call(replica, {:put, key, value})
    end

    :ok
  end

  def get(key), do: GenServer.call(__MODULE__, {:get, key})

  @doc "How many replicas this node can see."
  def count, do: length(:pg.get_members(:kv_replicas))

  @impl true
  def init(map) do
    :ok = :pg.join(:kv_replicas, self())
    {:ok, map}
  end

  @impl true
  def handle_call({:put, k, v}, _from, map), do: {:reply, :ok, Map.put_new(map, k, v)}
  def handle_call({:get, k}, _from, map), do: {:reply, Map.get(map, k), map}
end
