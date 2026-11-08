# A worker that waits for a message nobody sends, while
# jobs keep arriving: the kind of process that takes a
# node down by filling its memory.
defmodule Stuck do
  def wait do
    receive do
      :never -> :ok
    end
  end
end

worker = spawn(&Stuck.wait/0)
Process.register(worker, :stuck_worker)
for n <- 1..50_000, do: send(worker, {:job, n})

# Tell the shell which OS process to signal, then idle.
File.write!("node.pid", System.pid())
Process.sleep(:infinity)
