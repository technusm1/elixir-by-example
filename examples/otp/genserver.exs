# A `GenServer` is a process that holds state and
# handles requests one at a time. You write the
# callbacks; OTP provides the receive loop, timeouts,
# error reporting and supervision hooks. `use
# GenServer` declares the behaviour, and `@impl true`
# marks each callback (see
# [Protocols and Behaviours](/core/protocols)).
# `name: __MODULE__` registers the process under the
# module's name, so callers don't need its pid.
defmodule Counter do
  use GenServer

  # The client API: plain functions other processes
  # call. They hide the message format.
  def start_link(initial) do
    GenServer.start_link(__MODULE__, initial, name: __MODULE__)
  end

  def increment(by \\ 1), do: GenServer.cast(__MODULE__, {:increment, by})
  def value, do: GenServer.call(__MODULE__, :value)

  # Server callbacks run inside the GenServer process.
  # `handle_call/3` also gets `from`, which identifies
  # the caller (unused here).
  @impl true
  def init(initial) when is_integer(initial), do: {:ok, initial}

  @impl true
  def handle_call(:value, _from, count), do: {:reply, count, count}

  @impl true
  def handle_cast({:increment, by}, count), do: {:noreply, count + by}
end

# `call` is synchronous: it waits for a reply (5s
# timeout by default). `cast` is fire-and-forget.
{:ok, pid} = Counter.start_link(10)
Counter.increment()
Counter.increment(5)
IO.inspect(Counter.value(), label: "value")

# Messages are processed in order, so the casts above
# are applied before the call is answered. That
# ordering is per sender, and it's the reason a
# GenServer never needs locks.
IO.inspect(Process.alive?(pid), label: "alive?")

# Plain messages (not calls or casts), like timers or
# monitors, arrive in `handle_info/2`.
# `Process.send_after/3` mails a message after a
# delay, and returning `{:stop, reason, state}` ends
# the GenServer.
defmodule Ticker do
  use GenServer

  def start_link(parent), do: GenServer.start_link(__MODULE__, parent)

  @impl true
  def init(parent) do
    Process.send_after(self(), :tick, 10)
    {:ok, {parent, 0}}
  end

  @impl true
  def handle_info(:tick, {parent, 2}) do
    send(parent, :done)
    {:stop, :normal, {parent, 3}}
  end

  def handle_info(:tick, {parent, n}) do
    IO.puts("tick #{n}")
    Process.send_after(self(), :tick, 10)
    {:noreply, {parent, n + 1}}
  end
end

{:ok, _} = Ticker.start_link(self())

receive do
  :done -> IO.puts("ticker finished")
end

# > **Pitfall:** a GenServer is a *bottleneck by
# > design*: one process, one message at a time. Doing
# > slow work (HTTP calls, heavy computation) inside
# > `handle_call` blocks every other caller. Hand slow
# > work to a `Task`, or read hot data from
# > [ETS](/otp/ets) instead.
#
# > **Pitfall:** `GenServer.call/3` from inside the same
# > GenServer's callback deadlocks until the timeout,
# > because the process is busy waiting on itself.
