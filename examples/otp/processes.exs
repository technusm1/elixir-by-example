# A BEAM process is not an OS process or thread. It's
# a tiny isolated unit (a few KB) with its own heap,
# scheduled by the VM. Spawning millions is normal.
#
# `spawn/1` starts a function in a new process and
# returns immediately. The new process runs
# concurrently with the one that spawned it.
parent = self()

spawn(fn ->
  send(parent, {:hello, "from a new process"})
end)

receive do
  {:hello, text} -> IO.puts(text)
end

# Each process has its own memory. Rebinding a
# variable inside another process changes nothing
# here: there is no shared state to corrupt.
counter = 0

spawn(fn ->
  counter = counter + 100
  send(parent, {:child_saw, counter})
end)

receive do
  {:child_saw, n} -> IO.puts("child saw #{n}, parent still has #{counter}")
end

# Processes are cheap enough to use one per task.
# Here 10,000 processes each compute a square and
# report back; we collect results in order by
# matching on the index.
n = 10_000

for i <- 1..n do
  spawn(fn -> send(parent, {:square, i, i * i}) end)
end

squares =
  for i <- 1..n do
    receive do
      {:square, ^i, sq} -> sq
    end
  end

IO.puts("sum of squares 1..#{n}: #{Enum.sum(squares)}")

# A process ends when its function returns. A crash
# in a plain `spawn`ed process doesn't affect its
# parent, which is the start of "let it crash".
pid = spawn(fn -> :ok end)
ref = Process.monitor(pid)

receive do
  {:DOWN, ^ref, :process, ^pid, reason} -> IO.inspect(reason, label: "exited with")
end

IO.inspect(Process.alive?(pid), label: "alive?")

# `Process.info/2` peeks at a live process. Useful
# when debugging in IEx; here we look at ourselves.
{:message_queue_len, len} = Process.info(self(), :message_queue_len)
IO.inspect(len, label: "messages waiting")

# > **Pitfall:** `spawn` gives you no supervision and no
# > crash notifications. In real code, start processes
# > under a supervisor (`Task.Supervisor`,
# > `DynamicSupervisor`) so they're restarted, shut
# > down cleanly, and visible in observer tools.
#
# > **Pitfall:** sending a large data structure to
# > another process *copies* it (except large binaries,
# > which are reference-counted). Pass the data a
# > process needs, not your whole state.
