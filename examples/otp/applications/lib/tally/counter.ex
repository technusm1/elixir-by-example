defmodule Tally.Counter do
  use GenServer

  def start_link(name) do
    GenServer.start_link(__MODULE__, 0, name: {:via, Registry, {Tally.Names, name}})
  end

  def hit(pid), do: GenServer.call(pid, :hit)

  @impl true
  def init(count), do: {:ok, count}

  @impl true
  def handle_call(:hit, _from, count), do: {:reply, count + 1, count + 1}
end
