# Processes communicate only by sending messages.
# `send/2` drops a message in the target's mailbox and
# returns immediately; it never blocks and never fails,
# even if the target is dead.
send(self(), :first)
send(self(), {:greeting, "hi"})
send(self(), :last)

# `receive` takes the first message matching any
# clause. Messages from one sender arrive in the order
# they were sent.
receive do
  msg -> IO.inspect(msg, label: "got")
end

# *Selective receive*: a clause can skip ahead to a
# message that matches, leaving earlier ones in the
# mailbox for later.
receive do
  :last -> IO.puts("picked :last first")
end

receive do
  {:greeting, text} -> IO.puts("then the greeting: #{text}")
end

# `after` sets a timeout in milliseconds. Without it,
# `receive` waits forever.
receive do
  :never_sent -> :ok
after
  50 -> IO.puts("nothing arrived within 50 ms")
end

# `after 0` checks the mailbox without waiting. A
# common idiom to drain all pending messages. An
# anonymous function can't call itself by name, so
# `drain` takes itself as an argument to recurse.
for i <- 1..3, do: send(self(), {:job, i})

drain = fn drain, acc ->
  receive do
    {:job, i} -> drain.(drain, [i | acc])
  after
    0 -> Enum.reverse(acc)
  end
end

IO.inspect(drain.(drain, []), label: "drained")

# Request/reply: include your own pid so the other
# process knows where to answer, and a unique ref so
# you can match *this* reply and not a stale one.
server =
  spawn(fn ->
    receive do
      {:double, n, from, ref} -> send(from, {ref, n * 2})
    end
  end)

ref = make_ref()
send(server, {:double, 21, self(), ref})

receive do
  {^ref, result} -> IO.inspect(result, label: "reply")
after
  1_000 -> IO.puts("timed out")
end

# Sending to a dead process is silently ignored.
send(server, :anyone_there?)
IO.puts("send to a dead pid returned without error")

# > **Pitfall:** a `receive` that never matches some
# > message leaves it in the mailbox forever. Every
# > later `receive` rescans it, so the process gets
# > slower and leaks memory. Long-running loops need a
# > catch-all clause (log and drop), which is exactly
# > what GenServer's `handle_info/2` gives you.
#
# > **Pitfall:** don't forget the `^` in `{^ref, ...}`.
# > Without the pin, `ref` is rebound and the clause
# > matches *any* two-element tuple, including replies
# > meant for someone else.
