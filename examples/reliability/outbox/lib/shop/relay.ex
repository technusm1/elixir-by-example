defmodule Shop.Relay do
  @moduledoc """
  Publishes unsent outbox events, oldest first, and
  marks each one as published. It polls once a second;
  `flush/1` runs a pass right now.
  """
  use GenServer
  import Ecto.Query
  alias Shop.{Broker, OutboxEvent, Repo}

  @interval 1_000

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  def flush(opts \\ []), do: GenServer.call(__MODULE__, {:flush, opts})

  @impl true
  def init(nil) do
    Process.send_after(self(), :poll, @interval)
    {:ok, nil}
  end

  @impl true
  def handle_call({:flush, opts}, _from, state) do
    {:reply, publish_pending(opts), state}
  end

  @impl true
  def handle_info(:poll, state) do
    publish_pending([])
    Process.send_after(self(), :poll, @interval)
    {:noreply, state}
  end

  defp publish_pending(opts) do
    pending = Repo.all(from e in OutboxEvent, where: is_nil(e.published_at), order_by: e.id)

    for event <- pending do
      Broker.publish("outbox-#{event.id}", event.topic, event.payload)
      # Crash between sending and marking as sent.
      if opts[:crash_before_mark], do: Shop.crash("outbox-#{event.id} published, node stops")
      now = DateTime.utc_now(:second)
      Repo.update!(Ecto.Changeset.change(event, published_at: now))
    end

    length(pending)
  end
end
