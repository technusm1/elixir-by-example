# Backpressure slows producers down to the consumer's
# pace. That works when the producer can wait. An HTTP
# client on the other side of the internet can't be told
# to slow down: if the node accepts every request, the
# queue grows, every request waits longer, and soon all
# of them time out. Serving nobody is worse than serving
# some.
#
# *Load shedding* is refusing work on purpose so that
# the work you accept still finishes in time. A quick
# "busy, try again" (HTTP 503) beats a slow timeout.
# This page shows three places to shed.
#
# The worker used throughout: each job takes 20 ms.
defmodule Worker do
  use GenServer

  def start, do: GenServer.start(__MODULE__, [])

  @impl true
  def init(_), do: {:ok, []}

  @impl true
  def handle_call({:job, n}, _from, done) do
    Process.sleep(20)
    {:reply, {:ok, n}, [n | done]}
  end

  def handle_call(:done, _from, done), do: {:reply, Enum.reverse(done), done}

  @impl true
  def handle_cast({:job, n, deadline}, done) do
    if System.monotonic_time(:millisecond) > deadline do
      {:noreply, done}
    else
      Process.sleep(20)
      {:noreply, [n | done]}
    end
  end
end

# **1. Cap the work in flight.** Callers bump a shared
# counter before they call and drop it afterwards. With
# the counter at the limit, a caller is refused at once,
# without even sending a message. The counter is an
# atomic (see [Atomics](/otp/atomics)):
# `:atomics.add_get/3` adds and reads in one step, so
# concurrent callers can't both take the last slot.
defmodule Admission do
  def new, do: :atomics.new(1, [])

  def run(counter, limit, fun) do
    if :atomics.add_get(counter, 1, 1) > limit do
      :atomics.sub(counter, 1, 1)
      {:error, :overloaded}
    else
      try do
        fun.()
      after
        :atomics.sub(counter, 1, 1)
      end
    end
  end
end

# Twenty requests arrive together. Five are served; the
# other fifteen get an answer right away instead of
# waiting in line behind them.
{:ok, worker} = Worker.start()
counter = Admission.new()

tasks =
  for n <- 1..20 do
    Task.async(fn ->
      receive do
        :go -> Admission.run(counter, 5, fn -> GenServer.call(worker, {:job, n}) end)
      end
    end)
  end

for task <- tasks, do: send(task.pid, :go)

tasks
|> Task.await_many()
|> Enum.frequencies_by(fn
  {:ok, _} -> :served
  {:error, reason} -> reason
end)
|> IO.inspect(label: "20 at once, limit 5")

# **2. Look at the queue before adding to it.**
# `Process.info(pid, :message_queue_len)` tells you how
# far behind a process is. Here the worker is paused
# with `:sys.suspend/1` so the backlog builds up without
# a race, and the sender stops adding at 100.
{:ok, worker} = Worker.start()
:sys.suspend(worker)

shed =
  Enum.count(1..250, fn n ->
    {:message_queue_len, len} = Process.info(worker, :message_queue_len)

    if len >= 100 do
      true
    else
      GenServer.cast(worker, {:job, n, :infinity})
      false
    end
  end)

IO.inspect(Process.info(worker, :message_queue_len), label: "queue")
IO.inspect(shed, label: "shed")
:sys.resume(worker)

# **3. Skip work nobody is waiting for.** By the time a
# queued job reaches the worker, the client may have
# given up. Each job carries a deadline, and the worker
# drops jobs that are past it instead of doing them for
# no one. (Numbers sort before atoms in Erlang's term
# order, so no time is ever greater than `:infinity`:
# the jobs above never expire.)
{:ok, worker} = Worker.start()
:sys.suspend(worker)
soon = System.monotonic_time(:millisecond) + 20
for n <- 1..3, do: GenServer.cast(worker, {:job, n, soon})

# Those three wait in the paused queue past their
# deadline. Two more arrive with time to spare.
Process.sleep(100)
later = System.monotonic_time(:millisecond) + 10_000
for n <- 4..5, do: GenServer.cast(worker, {:job, n, later})
:sys.resume(worker)
IO.inspect(GenServer.call(worker, :done), label: "jobs actually done")

# > **Pitfall:** the queue length is a snapshot. Many
# > senders checking at once can all see 99 and all
# > send. As a soft limit that's fine; for a hard limit
# > use a counter like `Admission` above.
#
# > **Pitfall:** the counter must come down even when
# > the work crashes, or every crash leaks a slot until
# > nothing is admitted. That's what the `after` is for.
#
# > **Pitfall:** shed as early as possible. Refusing in
# > the HTTP layer, before parsing the body or touching
# > the database, costs almost nothing. Refusing after
# > the work is half done saves almost nothing.
