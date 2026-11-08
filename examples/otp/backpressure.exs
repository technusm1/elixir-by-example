# *Backpressure* means a slow consumer slows its
# producers down instead of letting work pile up in
# memory. `GenServer.call/3` gives you a little of it
# for free: the caller waits for the reply, so it can't
# get ahead. But `call` only stops a producer while its
# *own* request is in flight. To cap how much work is
# waiting in total, the server has to hold callers back
# on purpose.
#
# The tool is a *deferred reply*. A `handle_call/3`
# doesn't have to answer right away: it can return
# `{:noreply, state}`, keep the caller's `from`, and
# answer later with `GenServer.reply/2`. Until then the
# caller stays blocked inside its `call`.
#
# A bounded buffer built that way: `push/2` is answered
# at once while there is room, and held back while the
# buffer is full. Each `pop/1` frees a slot, so the
# oldest waiting producer gets in and is released.
defmodule Buffer do
  use GenServer

  def start_link(capacity), do: GenServer.start_link(__MODULE__, capacity)
  def push(buffer, item, timeout \\ :infinity), do: GenServer.call(buffer, {:push, item}, timeout)
  def pop(buffer), do: GenServer.call(buffer, :pop)
  def info(buffer), do: GenServer.call(buffer, :info)

  @impl true
  def init(capacity), do: {:ok, %{capacity: capacity, items: :queue.new(), waiting: :queue.new()}}

  @impl true
  def handle_call({:push, item}, from, state) do
    if :queue.len(state.items) < state.capacity do
      {:reply, :ok, %{state | items: :queue.in(item, state.items)}}
    else
      # Full: park the caller. No reply means it stays
      # blocked.
      {:noreply, %{state | waiting: :queue.in({from, item}, state.waiting)}}
    end
  end

  def handle_call(:pop, _from, state) do
    case :queue.out(state.items) do
      {:empty, _} ->
        {:reply, :empty, state}

      {{:value, item}, items} ->
        {:reply, {:ok, item}, admit_waiting(%{state | items: items})}
    end
  end

  def handle_call(:info, _from, state) do
    blocked = for {_from, item} <- :queue.to_list(state.waiting), do: item
    {:reply, %{items: :queue.to_list(state.items), blocked: blocked}, state}
  end

  # A slot is free: move the oldest waiting item in and
  # release its producer.
  defp admit_waiting(state) do
    case :queue.out(state.waiting) do
      {:empty, _} ->
        state

      {{:value, {from, item}}, waiting} ->
        GenServer.reply(from, :ok)
        %{state | items: :queue.in(item, state.items), waiting: waiting}
    end
  end
end

# The script waits for the other processes to reach a
# known state before printing, so the output doesn't
# depend on timing.
defmodule Wait do
  def until(check) do
    if check.(), do: :ok, else: Process.sleep(1) && until(check)
  end
end

# A producer pushes five items into a buffer with room
# for two. It gets two in and then blocks on the third.
{:ok, buffer} = Buffer.start_link(2)
parent = self()

producer =
  spawn(fn ->
    for item <- 1..5 do
      :ok = Buffer.push(buffer, item)
    end

    send(parent, :producer_done)
  end)

Wait.until(fn -> Buffer.info(buffer).blocked == [3] end)
IO.inspect(Buffer.info(buffer), label: "full")

# `Process.info/2` shows where the producer is: waiting
# inside `gen:do_call`, the receive that every `call`
# uses for its reply.
{:current_function, current} = Process.info(producer, :current_function)
IO.inspect(current, label: "producer is in")

# Every pop lets exactly one more item in. The producer
# moves at the consumer's pace, and the buffer never
# holds more than two.
for _ <- 1..2 do
  IO.inspect(Buffer.pop(buffer), label: "pop")
  Wait.until(fn -> length(Buffer.info(buffer).blocked) == 1 end)
  IO.inspect(Buffer.info(buffer), label: "now")
end

for _ <- 1..3, do: IO.inspect(Buffer.pop(buffer), label: "pop")

receive do
  :producer_done -> IO.puts("producer finished")
end

# Several producers queue up behind a full buffer in
# arrival order, one waiting entry each. That's the
# whole cost of backpressure: one blocked process per
# producer, not an unbounded pile of messages.
{:ok, buffer} = Buffer.start_link(1)
:ok = Buffer.push(buffer, :a)

for item <- [:b, :c, :d] do
  spawn(fn -> Buffer.push(buffer, item) end)
  Wait.until(fn -> List.last(Buffer.info(buffer).blocked) == item end)
end

IO.inspect(Buffer.info(buffer), label: "three producers waiting")

# > **Pitfall:** a call timeout doesn't cancel the
# > request. When a blocked `push` gives up, the caller
# > exits with a timeout (caught here), but its item is
# > still parked in the server, and the next free slot
# > takes it. The producer thinks it failed; the item
# > goes through anyway.
{:ok, buffer} = Buffer.start_link(1)
:ok = Buffer.push(buffer, :first)

try do
  Buffer.push(buffer, :gave_up, 50)
catch
  :exit, {:timeout, _} -> IO.puts("push timed out after 50 ms")
end

IO.inspect(Buffer.pop(buffer), label: "pop")
IO.inspect(Buffer.info(buffer), label: "after the timeout")

# > If the producer is going to retry, make that safe:
# > give each item an id and drop duplicates, or have
# > the server check whether the caller is still alive
# > (monitor it) before admitting its item.
#
# > **Pitfall:** `cast` skips all of this. A producer
# > that casts never waits, so a bounded buffer behind a
# > `cast` API is bounded in name only: the overflow
# > just moves into the server's mailbox (see
# > [Mailboxes and Slow Consumers](/production/mailboxes)).
#
# > **Pitfall:** the default call timeout is 5 seconds.
# > A producer that is *supposed* to wait for a slow
# > consumer needs `:infinity` or a timeout that fits,
# > otherwise ordinary backpressure looks like a crash.
#
# The same idea, the consumer setting the pace, is what
# [GenStage](https://hexdocs.pm/gen_stage) and
# [Broadway](https://hexdocs.pm/broadway) build on:
# consumers ask for a number of events, and producers
# never send more than was asked for.
