# Registered names (`name: :foo`) must be atoms, and
# atoms are never garbage collected. To name thousands
# of dynamic processes (one per user, room, bucket)
# use a `Registry`, which maps any term to a pid.
{:ok, _} = Registry.start_link(keys: :unique, name: Rooms)

defmodule Room do
  use GenServer

  # A `:via` tuple tells GenServer to register the
  # name through Registry instead of the atom table.
  def via(id), do: {:via, Registry, {Rooms, id}}

  def start_link(id), do: GenServer.start_link(__MODULE__, id, name: via(id))

  def join(id, user), do: GenServer.call(via(id), {:join, user})

  @impl true
  def init(id), do: {:ok, %{id: id, users: []}}

  @impl true
  def handle_call({:join, user}, _from, state) do
    users = [user | state.users]
    {:reply, Enum.reverse(users), %{state | users: users}}
  end
end

# Names can be strings, tuples, anything.
{:ok, _} = Room.start_link("lobby")
{:ok, _} = Room.start_link({:game, 42})

Room.join("lobby", "ada")
IO.inspect(Room.join("lobby", "grace"), label: "lobby")
IO.inspect(Room.join({:game, 42}, "joe"), label: "game 42")

# Unique keys: starting a second "lobby" fails with
# the existing pid, so callers can just use it.
{:error, {:already_started, _pid}} = Room.start_link("lobby")
IO.puts("second lobby refused")

# Look up and count without knowing pids.
[{_pid, _value}] = Registry.lookup(Rooms, "lobby")
IO.inspect(Registry.lookup(Rooms, "attic"), label: "attic")
IO.inspect(Registry.count(Rooms), label: "rooms")

# Entries are removed automatically when the process
# dies, but *asynchronously*: the Registry learns about
# the exit from a message. Right after `stop` a lookup
# may still return the dead pid, so code that needs
# the name gone has to wait for it.
GenServer.stop(Room.via({:game, 42}))

wait_until_gone = fn again ->
  case Registry.lookup(Rooms, {:game, 42}) do
    [] -> []
    _still_there -> Process.sleep(1) && again.(again)
  end
end

IO.inspect(wait_until_gone.(wait_until_gone), label: "after stop")

# `keys: :duplicate` lets many processes register
# under the same key: a local pub/sub. Each subscriber
# registers itself, and `dispatch/3` reaches them all.
{:ok, _} = Registry.start_link(keys: :duplicate, name: PubSub)
parent = self()

for name <- ["a", "b", "c"] do
  spawn(fn ->
    {:ok, _} = Registry.register(PubSub, "news", name)
    send(parent, :subscribed)

    receive do
      {:broadcast, msg} -> send(parent, {:got, name, msg})
    end
  end)
end

for _ <- 1..3, do: receive(do: (:subscribed -> :ok))

Registry.dispatch(PubSub, "news", fn entries ->
  for {pid, _name} <- entries, do: send(pid, {:broadcast, "hello"})
end)

got = for _ <- 1..3, do: receive(do: ({:got, name, msg} -> {name, msg}))
IO.inspect(Enum.sort(got), label: "delivered")

# > **Pitfall:** `String.to_atom("room_" <> id)` to name
# > dynamic processes leaks atoms; the atom table has a
# > fixed limit (about a million by default) and the VM
# > crashes when it's full. Use a Registry.
#
# > **Pitfall:** "the process stopped, so its name is
# > free" is a race. This example once printed the dead
# > pid when run in the browser and `[]` natively. Start
# > the replacement and handle `{:already_started, pid}`,
# > or wait as above; don't assume instant cleanup.
#
# > **Pitfall:** Registry is *local to one node*. In a
# > cluster, a name registered on node A is invisible on
# > node B. For cluster-wide names look at `:global`,
# > or `:pg` for groups (see the Distributed track).
