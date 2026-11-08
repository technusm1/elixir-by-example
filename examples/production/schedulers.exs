# The BEAM runs one *scheduler* thread per CPU core, and
# each scheduler runs processes from its own run queue.
# It doesn't wait for a process to give up the CPU: it
# counts the work the process does in *reductions*
# (roughly, function calls) and switches to the next
# process once a budget of a few thousand is spent. So
# one process stuck in a loop can't freeze the others,
# and reductions are the number to look at when a node
# is busy and you want to know who's doing the work.
#
# This page runs with a single scheduler (`elixir --erl
# "+S 1"`), so every process has to share one thread.
IO.inspect(System.schedulers_online(), label: "schedulers")

# A process that never stops: an endless tail-recursive
# loop. It never waits for a message, so it never gives
# up the CPU by itself. `Process.register/2` gives it a
# name, so it's easy to recognize when we go looking for
# the busiest process below.
defmodule Spin do
  def forever(n), do: forever(n + 1)
end

busy = spawn(fn -> Spin.forever(0) end)
Process.register(busy, :busy)

# And one that only waits.
idle = spawn(fn -> receive do: (:never -> :ok) end)
Process.register(idle, :idle)

# With the loop running on the only scheduler, another
# process still gets to answer a message, and this script
# still gets to read the answer. The scheduler preempts
# the loop each time its budget runs out.
me = self()
pinger = spawn(fn -> receive do: ({:ping, from} -> send(from, :pong)) end)
send(pinger, {:ping, me})
receive do: (:pong -> IO.puts("got :pong while the loop runs"))

# Which process is burning the CPU? Every process's
# reduction count only goes up, so take two snapshots
# and compare. The process whose count grew the most is
# the busy one. This is what `recon`'s `proc_window/3`
# and `observer_cli` do on a live node.
snapshot = fn ->
  for pid <- Process.list(),
      {:reductions, count} <- [Process.info(pid, :reductions)],
      into: %{},
      do: {pid, count}
end

before = snapshot.()
Process.sleep(100)
later = snapshot.()

[{top, grew} | _] =
  later
  |> Enum.map(fn {pid, count} -> {pid, count - Map.get(before, pid, 0)} end)
  |> Enum.sort_by(fn {_pid, grew} -> grew end, :desc)

IO.inspect(Process.info(top, :registered_name), label: "busiest process")
IO.inspect(grew > 1_000_000, label: "over a million reductions in 100 ms")

{:reductions, idle_count} = Process.info(idle, :reductions)
IO.inspect(idle_count < 100, label: "the idle one barely ran")

Process.exit(busy, :kill)

# > **Pitfall:** preemption only happens in Erlang and
# > Elixir code. A NIF (a function written in C or Rust
# > and loaded into the VM) runs until it returns, and
# > the scheduler running it can't serve anyone else in
# > the meantime. A NIF that may take more than about a
# > millisecond must run on a *dirty scheduler*, a
# > separate pool of threads for long native work
# > (`ERL_NIF_DIRTY_JOB_CPU_BOUND` in C,
# > `#[rustler::nif(schedule = "DirtyCpu")]` with
# > Rustler). See [Ports and NIFs](/otp/ports-and-nifs).
#
# > **Pitfall:** `Process.flag(:priority, :high)` looks
# > like a fix for a slow process, but a high-priority
# > process that is always busy starves every normal
# > one, including the ones the system needs to stay
# > healthy. Find out why the process is slow instead.
#
# > **Pitfall:** high CPU with low throughput often means
# > run queues are long, not that one process is slow.
# > `:erlang.statistics(:total_run_queue_lengths)` shows
# > how many processes are waiting for a scheduler. A
# > number that stays above the number of schedulers
# > means the node has more work than cores.
#
# **Go deeper:** chapter 10 of [The BEAM Book](https://blog.stenmans.org/theBeamBook/#CH-Scheduling)
# by Erik Stenman, "Scheduling", covers run queues,
# process states, load balancing between schedulers,
# and how ports are scheduled.
