# Processes fail independently, but you usually need
# to *know* when one fails. Links and monitors are the
# two ways to find out.
#
# Crash reports are logged by default, and they
# include pids that change on every run. We silence
# the logger so the output below stays readable.
Logger.configure(level: :none)

# A **link** is bidirectional: if either process dies
# abnormally, the other gets an exit signal and, by
# default, dies too. Processes that must live and die
# together are linked.
#
# To survive the signal and receive it as a message
# instead, a process *traps exits*. Supervisors work
# exactly like this.
Process.flag(:trap_exit, true)

pid = spawn_link(fn -> raise "boom" end)

receive do
  {:EXIT, ^pid, {%RuntimeError{message: msg}, _stack}} ->
    IO.puts("linked process crashed: #{msg}")
end

# A normal exit doesn't kill linked processes. With
# trap_exit on we still see it, with reason `:normal`.
pid = spawn_link(fn -> :ok end)

receive do
  {:EXIT, ^pid, reason} -> IO.inspect(reason, label: "normal exit")
end

Process.flag(:trap_exit, false)

# A **monitor** is one-way and never kills anyone. The
# watcher gets a `:DOWN` message when the target exits,
# for any reason. Use monitors when you only want to
# observe, like a client watching a server.
# `exit(reason)` ends the calling process with that
# reason (more in [Errors](/core/errors)).
pid = spawn(fn -> exit(:shutting_down) end)
ref = Process.monitor(pid)

receive do
  {:DOWN, ^ref, :process, ^pid, reason} -> IO.inspect(reason, label: "monitor saw")
end

# Monitoring a process that's already dead still
# works: you get `:DOWN` immediately with reason
# `:noproc`. No race between "is it alive?" and
# "watch it".
ref = Process.monitor(pid)

receive do
  {:DOWN, ^ref, :process, _, reason} -> IO.inspect(reason, label: "already dead")
end

# Stop watching with `Process.demonitor/2`. `:flush`
# also removes a `:DOWN` that may already be queued.
# `Process.exit(pid, :kill)` then kills the process
# unconditionally; it can't trap a `:kill`.
pid = spawn(fn -> Process.sleep(:infinity) end)
ref = Process.monitor(pid)
true = Process.demonitor(ref, [:flush])
Process.exit(pid, :kill)
IO.puts("demonitored; no :DOWN will arrive")

# > **Pitfall:** linking to a process you don't own
# > (say, from a short-lived web request to a shared
# > worker) means its crash takes you down, and yours
# > may take *it* down. Observe with a monitor; link
# > only for "these must die together".
#
# > **Pitfall:** `Process.alive?/1` followed by
# > `send/2` is a race: the process can die in between.
# > Monitor it (or use `GenServer.call`, which monitors
# > for you) and handle `:DOWN`.
