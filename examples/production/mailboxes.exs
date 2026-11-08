# Sending a message never blocks: it lands in the
# receiver's mailbox, however full that is. That makes
# the BEAM fast and simple, and it means a process that
# receives faster than it can work quietly piles up
# messages until the node runs out of memory. A growing
# `message_queue_len` is one of the most common causes
# of a slow or crashing node, so it's the first number to
# check.
#
# A slow worker: each job takes a millisecond. It
# remembers the longest queue it has seen behind it.
defmodule Slow do
  use GenServer

  def init(_), do: {:ok, 0}

  def handle_cast(:job, longest), do: {:noreply, work(longest)}
  def handle_call(:job, _from, longest), do: {:reply, :ok, work(longest)}
  def handle_call(:longest, _from, longest), do: {:reply, longest, longest}

  defp work(longest) do
    Process.sleep(1)
    {:message_queue_len, waiting} = Process.info(self(), :message_queue_len)
    max(longest, waiting)
  end
end

# `cast` returns at once, so a fast caller can hand out
# work much faster than the worker finishes it. To see
# the backlog without a race, the worker is paused with
# `:sys.suspend/1` while the jobs arrive.
{:ok, worker} = GenServer.start(Slow, nil)
{:memory, empty} = Process.info(worker, :memory)

:sys.suspend(worker)
for _ <- 1..1000, do: GenServer.cast(worker, :job)

IO.inspect(Process.info(worker, :message_queue_len), label: "after 1000 casts")
{:memory, full} = Process.info(worker, :memory)
IO.inspect(full > 10 * empty, label: "the mailbox takes memory")

:sys.resume(worker)

# `call` waits for the reply, so a caller can never get
# ahead of the worker: the queue behind it stays empty.
# That's back-pressure. The caller slows down to the
# worker's pace instead of burying it.
{:ok, worker} = GenServer.start(Slow, nil)
for _ <- 1..1000, do: GenServer.call(worker, :job)
IO.inspect(GenServer.call(worker, :longest), label: "longest queue with call")

# A `receive` doesn't take the oldest message. It scans
# the mailbox from the oldest and takes the first one
# that matches, leaving the rest where they are. This is
# *selective receive*.
for n <- 1..3, do: send(self(), {:job, n})
send(self(), :urgent)

receive do
  :urgent -> IO.puts("handled :urgent first")
end

IO.inspect(Process.info(self(), :messages), label: "still waiting")

# > **Pitfall:** with a long queue, selective receive gets
# > slow: every `receive` scans past every message that
# > doesn't match. A process that is behind falls further
# > behind, because each message costs more to reach. The
# > compiler avoids the scan for the common case, a
# > `receive` that matches a reference created just
# > before (that's how `GenServer.call/3` waits for its
# > reply), but not for patterns in general.
#
# > **Pitfall:** `cast` and `send` to a busy process from
# > many processes at once is the classic way to fill a
# > mailbox: loggers, metrics collectors and "fire and
# > forget" notifications. Use `call` where the caller
# > can afford to wait, spread the work over several
# > processes, or drop work on purpose when the queue is
# > too long.
#
# > **Pitfall:** a process with a big mailbox also slows
# > down garbage collection, because the messages are on
# > its heap. `Process.flag(:message_queue_data, :off_heap)`
# > keeps them off the heap; it helps for processes
# > that are expected to receive bursts, like a logger.
#
# **Go deeper:** [The BEAM Book](https://blog.stenmans.org/theBeamBook/#_mailboxes_and_message_passing)
# by Erik Stenman, sections 3.5 and 3.6, shows how
# mailboxes are built and why sending needs no locks.
