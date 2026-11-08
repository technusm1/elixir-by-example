# A supervisor starts child processes, watches them,
# and restarts them when they crash. This is "let it
# crash" in practice: instead of defensive code for
# every failure, you return to a known good state.
#
# Elixir has two kinds. A `Supervisor` starts a fixed
# list of children when it starts. A `DynamicSupervisor`
# starts empty, and you add children while the program
# runs.
#
# Crash reports would print pids that change every
# run, so we silence the logger for this example.
Logger.configure(level: :none)

# A stand-in for real services: it prints when it
# starts, and crashes on request.
defmodule Service do
  use GenServer

  def start_link(name), do: GenServer.start_link(__MODULE__, name, name: name)

  @impl true
  def init(name) do
    IO.puts("  start #{name}")
    {:ok, name}
  end

  @impl true
  def handle_call(:crash, _from, _name), do: raise("simulated bug")
end

# ## Child specs
#
# A supervisor needs a *child spec* for each child: an
# `id`, and the `{module, function, args}` that starts
# it. `use GenServer` generates `child_spec/1`, so the
# tuple `{Service, :db}` is enough (and a bare `Service`
# means `{Service, []}`).
IO.inspect(Service.child_spec(:db), label: "child spec")

# Ids must be unique within a supervisor. All three
# children here come from the same module, so each
# gets its own id with `Supervisor.child_spec/2`.
children = for name <- [:db, :cache, :api], do: Supervisor.child_spec({Service, name}, id: name)

# A crashing call exits the caller too (see
# [Errors](/core/errors)), so this helper catches that
# exit.
crash = fn name ->
  try do
    GenServer.call(name, :crash)
  catch
    :exit, _ -> :crashed
  end
end

# ## Strategies
#
# The strategy decides *which* children restart when
# one crashes. Children start in list order, so here
# `api` depends on `cache`, which depends on `db`:
#
# - `:one_for_one`: only the crashed child.
# - `:rest_for_one`: the crashed child and every child
#   started after it.
# - `:one_for_all`: all of them.
#
# A call to the supervisor returns only after it has
# handled the crash, so `which_children/1` doubles as
# "wait for the restart".
for strategy <- [:one_for_one, :rest_for_one, :one_for_all] do
  IO.puts("#{strategy}:")
  {:ok, sup} = Supervisor.start_link(children, strategy: strategy)
  IO.puts("  -- cache crashes --")
  crash.(:cache)
  _ = Supervisor.which_children(sup)
  Supervisor.stop(sup)
end

# Pick the strategy from the dependencies: independent
# children want `:one_for_one`; a child that can't work
# without the ones before it wants `:rest_for_one`;
# children that share state no one else can rebuild
# want `:one_for_all`.

# ## Restart types
#
# Each child also has a *restart type*, set in its
# child spec, for example `use GenServer, restart:
# :transient`:
#
# - `:permanent` (the default): always restarted.
# - `:transient`: restarted only after a crash, not
#   after a normal exit. For work that can finish.
# - `:temporary`: never restarted.

# Restarts are rate limited: more than `max_restarts`
# within `max_seconds` (defaults: 3 in 5 s) and the
# supervisor itself gives up and exits with reason
# `:shutdown`, passing the failure up to *its*
# supervisor. Trapping exits (see
# [Links and Monitors](/otp/links-and-monitors)) turns
# that exit into a message we can print.
IO.puts("max_restarts: 1")
Process.flag(:trap_exit, true)
{:ok, sup} = Supervisor.start_link([{Service, :db}], strategy: :one_for_one, max_restarts: 1)
crash.(:db)
_ = Supervisor.which_children(sup)
crash.(:db)

receive do
  {:EXIT, ^sup, reason} -> IO.inspect(reason, label: "supervisor exited")
end

# ## DynamicSupervisor
#
# Some children don't exist when the program starts: a
# process per game room, per upload, per connected
# user. A `DynamicSupervisor` starts empty and
# `start_child/2` adds a child spec at runtime.
#
# A room can close normally when its game ends, or
# crash. `:transient` restarts it only in the second
# case.
defmodule Room do
  use GenServer, restart: :transient

  def start_link(name), do: GenServer.start_link(__MODULE__, name)

  @impl true
  def init(name) do
    IO.puts("  room #{name} opens")
    {:ok, name}
  end

  # `{:stop, reason, reply, state}` replies, then stops
  # the process with that reason.
  @impl true
  def handle_call(:close, _from, name), do: {:stop, :normal, :ok, name}
  def handle_call(:crash, _from, _name), do: raise("simulated bug")
end

# Supervisors nest: this top-level supervisor starts
# the `DynamicSupervisor` as one of its children.
# That's a *supervision tree*. `name: Rooms` registers
# it under the atom `Rooms` (any atom works, no module
# needed), so we can reach it without its pid.
tree = [{DynamicSupervisor, name: Rooms, strategy: :one_for_one}]
{:ok, _top} = Supervisor.start_link(tree, strategy: :one_for_one)

IO.puts("players open three rooms:")
{:ok, lobby} = DynamicSupervisor.start_child(Rooms, {Room, "lobby"})
{:ok, chess} = DynamicSupervisor.start_child(Rooms, {Room, "chess"})
{:ok, _go} = DynamicSupervisor.start_child(Rooms, {Room, "go"})
IO.inspect(DynamicSupervisor.count_children(Rooms).active, label: "rooms")

IO.puts("the chess game ends:")
GenServer.call(chess, :close)
_ = DynamicSupervisor.which_children(Rooms)
IO.inspect(DynamicSupervisor.count_children(Rooms).active, label: "rooms")

IO.puts("the lobby crashes:")
crash.(lobby)
_ = DynamicSupervisor.which_children(Rooms)
IO.inspect(DynamicSupervisor.count_children(Rooms).active, label: "rooms")

# When to use which:
#
# - **`Supervisor`** for the fixed parts of your
#   program, known at startup: a cache, a connection
#   pool, a scheduler. It restarts them with the
#   strategy you chose.
# - **`DynamicSupervisor`** for children created on
#   demand, any number of them, all alike. It's always
#   `:one_for_one`.
# - **`Task.Supervisor`** (see [Task](/otp/task)) for
#   one-off tasks, which are `:temporary`.
#
# Real programs combine them into one tree, with a
# `Supervisor` at the top.

# > **Pitfall:** a supervisor restarts a child with its
# > *initial* arguments. State held only in the process
# > is gone after a crash. Keep state you can't lose in
# > ETS, a database, or another process.
#
# > **Pitfall:** don't do slow or failure-prone work in
# > `init/1` (connecting to a database, HTTP calls).
# > The supervisor waits while each child starts, and a
# > failing `init` crash-loops into `max_restarts`.
# > Return `{:ok, state, {:continue, :connect}}`
# > instead: `start_link` returns at once, and the
# > GenServer runs `handle_continue(:connect, state)`
# > before it handles any message.
#
# > **Pitfall:** a `DynamicSupervisor` is one process.
# > If thousands of children start per second, it
# > becomes the bottleneck; `PartitionSupervisor` runs
# > several of them and spreads the children across.
