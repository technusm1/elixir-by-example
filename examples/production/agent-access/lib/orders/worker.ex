defmodule Orders.Worker do
  @moduledoc """
  Charges orders one at a time. Today the payment provider hangs, so the first
  charge never returns and every later order waits in the mailbox.
  """
  use GenServer

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  def charge(order_id), do: GenServer.cast(__MODULE__, {:charge, order_id})

  @impl true
  def init(nil), do: {:ok, nil}

  @impl true
  def handle_cast({:charge, order_id}, state) do
    :ok = call_payment_provider(order_id)
    {:noreply, state}
  end

  # Stands in for an HTTP call without a timeout to a provider that never answers.
  defp call_payment_provider(_order_id) do
    receive do
      :never_sent -> :ok
    end
  end
end
