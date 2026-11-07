# `Task` runs a one-off computation in a process and
# gives you its result. It's the friendly face of
# spawn + monitor + receive.
task = Task.async(fn -> Enum.sum(1..1_000) end)
IO.inspect(Task.await(task), label: "sum")

# Start several, then await them all. They run
# concurrently, so total time is roughly the slowest
# one, not the sum.
tasks = for n <- [3, 1, 2], do: Task.async(fn -> Process.sleep(n * 10) && n * n end)
IO.inspect(Task.await_many(tasks), label: "squares, in start order")

# `Task.async_stream/3` maps over a collection with a
# concurrency limit: the right tool for "call this API
# for 10,000 items, but at most 8 at a time".
results =
  1..10
  |> Task.async_stream(fn n -> n * 10 end, max_concurrency: 4)
  |> Enum.map(fn {:ok, value} -> value end)

IO.inspect(results, label: "async_stream")

# `Task.yield/2` waits up to a timeout and returns
# `nil` if the task isn't done, so *you* decide what
# to do. `Task.shutdown/2` then stops it.
slow = Task.async(fn -> Process.sleep(:infinity) end)

case Task.yield(slow, 50) || Task.shutdown(slow) do
  {:ok, value} -> IO.inspect(value)
  nil -> IO.puts("gave up after 50 ms and shut the task down")
end

# `Task.async` *links* the task to the caller, so a
# crashing task crashes the caller too. For work that
# may fail, start tasks under a `Task.Supervisor` with
# `async_nolink` and handle the failure as a value.
Logger.configure(level: :none)
{:ok, sup} = Task.Supervisor.start_link()

risky = Task.Supervisor.async_nolink(sup, fn -> raise "upstream timeout" end)

case Task.yield(risky, 1_000) || Task.shutdown(risky) do
  {:ok, value} -> IO.inspect(value)
  {:exit, {%RuntimeError{message: msg}, _}} -> IO.puts("task failed: #{msg}")
  nil -> IO.puts("no answer")
end

# Fire-and-forget work that should still be
# supervised: `Task.Supervisor.start_child/2`.
parent = self()
{:ok, _} = Task.Supervisor.start_child(sup, fn -> send(parent, :background_done) end)

receive do
  :background_done -> IO.puts("background task finished")
end

# > **Pitfall:** `Task.await/2` has a 5 second default
# > timeout, and on timeout it *exits the caller*. It
# > doesn't return an error tuple. Pass a timeout that
# > fits the work, or use `yield`/`shutdown`.
#
# > **Pitfall:** calling `Task.async` inside a GenServer
# > and never awaiting it leaves a reply message (and a
# > `:DOWN`) in the GenServer's mailbox. Either await
# > it, or use `Task.Supervisor.async_nolink` and handle
# > `{ref, result}` and `{:DOWN, ...}` in `handle_info`.
