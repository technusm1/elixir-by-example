defmodule Tally.Total do
  use GenServer

  def start_link(_opts), do: GenServer.start_link(__MODULE__, 0, name: __MODULE__)

  def add, do: GenServer.cast(__MODULE__, :add)
  def get, do: GenServer.call(__MODULE__, :get)

  @impl true
  def init(total), do: {:ok, total}

  @impl true
  def handle_cast(:add, total), do: {:noreply, total + 1}

  @impl true
  def handle_call(:get, _from, total), do: {:reply, total, total}
end
