defmodule Shop do
  alias Shop.{Broker, Order, OutboxEvent, Repo}
  alias Ecto.Multi

  def orders, do: Order |> Repo.all() |> Enum.map(&{&1.id, &1.item})

  # The dual write: save the order, then tell the broker.
  # `crash_after_commit: true` stops the node between the
  # two, like a deploy or an out-of-memory kill would.
  def place_order_dual_write(item, opts \\ []) do
    {:ok, order} = Repo.insert(%Order{item: item})
    if opts[:crash_after_commit], do: crash("order #{order.id} committed, node stops")
    Broker.publish("dual-#{order.id}", "order_placed", %{"item" => item})
    {:ok, order.id}
  end

  # The outbox: the order and the event are saved in the
  # same transaction. Nothing is sent here. The relay
  # sends it later, from the table.
  def place_order(item, opts \\ []) do
    {:ok, %{order: order}} =
      Multi.new()
      |> Multi.insert(:order, %Order{item: item})
      |> Multi.insert(:event, %OutboxEvent{topic: "order_placed", payload: %{"item" => item}})
      |> Repo.transaction()

    if opts[:crash_after_commit], do: crash("order #{order.id} committed, node stops")
    {:ok, order.id}
  end

  # Stands in for a deploy or an out-of-memory kill: the
  # node stops on the spot, with exit status 1.
  def crash(message) do
    IO.puts(message)
    System.halt(1)
  end
end
