# A supervisor starts child processes, watches them,
# and restarts them when they crash. This is "let it
# crash" in practice: instead of defensive code for
# every failure, you return to a known good state.
#
# Crash reports would print pids that change every
# run, so we silence the logger for this example.
Logger.configure(level: :none)

defmodule Worker do
  use GenServer

  def start_link(name), do: GenServer.start_link(__MODULE__, name, name: name)

  @impl true
  def init(name) do
    IO.puts("starting #{inspect(name)}")
    {:ok, name}
  end

  @impl true
  def handle_call(:crash, _from, _state), do: raise("simulated bug")
end

# A child spec says how to start a child and how to
# restart it. `use GenServer` generates one, so a
# `{Module, arg}` tuple is enough.
children = [
  Supervisor.child_spec({Worker, :a}, id: :a),
  Supervisor.child_spec({Worker, :b}, id: :b),
  Supervisor.child_spec({Worker, :c}, id: :c)
]

# `:one_for_one`: only the crashed child restarts.
{:ok, sup} = Supervisor.start_link(children, strategy: :one_for_one)

# Crash `:b`. The call fails in the caller too (it
# exits), so we catch that exit with a small helper.
crash = fn name ->
  try do
    GenServer.call(name, :crash)
  catch
    :exit, _ -> :crashed
  end
end

pid_before = Process.whereis(:b)
crash.(:b)

# Wait until the supervisor has restarted `:b`. The
# restart is synchronous inside the supervisor, so a
# call to the supervisor returns after it's done.
_ = Supervisor.which_children(sup)
IO.inspect(Process.whereis(:b) != pid_before, label: "b has a new pid")
IO.inspect(Supervisor.count_children(sup), label: "children")
Supervisor.stop(sup)

# `:one_for_all`: one crash restarts every child. Use
# it when children depend on each other's state.
# (`:rest_for_one` restarts the crashed child and the
# ones started after it.)
IO.puts("-- one_for_all --")
{:ok, sup} = Supervisor.start_link(children, strategy: :one_for_all)
crash.(:a)
_ = Supervisor.which_children(sup)
Supervisor.stop(sup)

# Restarts are rate limited: more than `max_restarts`
# within `max_seconds` (defaults: 3 in 5s) and the
# supervisor itself gives up and exits (with reason
# `:shutdown`), escalating the
# failure to *its* supervisor.
IO.puts("-- max_restarts: 1 --")
Process.flag(:trap_exit, true)

{:ok, sup} =
  Supervisor.start_link([Supervisor.child_spec({Worker, :a}, id: :a)],
    strategy: :one_for_one,
    max_restarts: 1
  )

crash.(:a)
_ = Supervisor.which_children(sup)
crash.(:a)

receive do
  {:EXIT, ^sup, reason} -> IO.inspect(reason, label: "supervisor exited")
end

# > **Pitfall:** a supervisor restarts a child with its
# > *initial* arguments. State held only in the process
# > is gone after a crash. Keep state you can't lose in
# > ETS, a database, or another process.
#
# > **Pitfall:** don't do slow or failure-prone work in
# > `init/1` (connecting to a database, HTTP calls).
# > The supervisor blocks while children start, and a
# > failing `init` crash-loops into `max_restarts`. Use
# > `{:ok, state, {:continue, :connect}}` instead.
