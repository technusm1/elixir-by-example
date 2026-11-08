defmodule Quota.Meter do
  @moduledoc """
  Counts hits per key and forgets them every `interval` milliseconds. When a
  key goes over `limit`, sends `{:over_limit, key}` to the `notify` process.
  """
  use GenServer

  @doc """
  Options: `limit` and `interval` (required), `notify` (a pid, optional) and
  `name` (optional).
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    GenServer.start_link(__MODULE__, opts, if(name, do: [name: name], else: []))
  end

  @doc "Records a hit and returns the key's count since the last reset."
  @spec hit(GenServer.server(), term()) :: pos_integer()
  def hit(meter, key), do: GenServer.call(meter, {:hit, key})

  @doc "The key's count since the last reset."
  @spec count(GenServer.server(), term()) :: non_neg_integer()
  def count(meter, key), do: GenServer.call(meter, {:count, key})

  @impl true
  def init(opts) do
    state = %{
      limit: Keyword.fetch!(opts, :limit),
      interval: Keyword.fetch!(opts, :interval),
      notify: Keyword.get(opts, :notify),
      counts: %{}
    }

    schedule_reset(state.interval)
    {:ok, state}
  end

  @impl true
  def handle_call({:hit, key}, _from, state) do
    count = Map.get(state.counts, key, 0) + 1
    if count == state.limit + 1 and state.notify, do: send(state.notify, {:over_limit, key})
    {:reply, count, put_in(state.counts[key], count)}
  end

  def handle_call({:count, key}, _from, state) do
    {:reply, Map.get(state.counts, key, 0), state}
  end

  @impl true
  def handle_info(:reset, state) do
    schedule_reset(state.interval)
    {:noreply, %{state | counts: %{}}}
  end

  defp schedule_reset(interval), do: Process.send_after(self(), :reset, interval)
end
