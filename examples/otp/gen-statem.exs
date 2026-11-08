# Many processes are really *state machines*: a
# connection is connecting, connected or closed; an
# order is new, paid or shipped. You can write one as a
# GenServer with a `status` field, but every callback
# then starts with "which state am I in?", and
# timers you forgot to cancel fire in the wrong state.
#
# `:gen_statem` is OTP's behaviour for state machines.
# It keeps the current state apart from the data, and it
# adds things a GenServer doesn't have:
#
# - **state enter calls**: code that runs every time a
#   state is entered, whichever way you got there.
# - **state timeouts**: timers cancelled automatically
#   when the state changes.
# - **postpone**: "I can't handle this event in this
#   state; give it to me again after the next state
#   change."
#
# Elixir has no wrapper for it, so you call the Erlang
# module directly.
#
# A pedestrian crossing. Cars have a light that goes
# green, yellow, red. A pedestrian calls `cross/1`,
# which returns only when it's safe to walk.
defmodule Crossing do
  @behaviour :gen_statem

  def start_link, do: :gen_statem.start_link(__MODULE__, [], [])
  def cross(crossing), do: :gen_statem.call(crossing, :cross)
  def light(crossing), do: :gen_statem.call(crossing, :light)

  # `:state_functions` means one function per state:
  # `green/3`, `yellow/3`, `red/3`. Each gets the event
  # type, the event and the data. `:state_enter` turns
  # on enter calls.
  @impl true
  def callback_mode, do: [:state_functions, :state_enter]

  # `init/1` returns the first state and the data. The
  # data here counts the people who crossed.
  @impl true
  def init([]), do: {:ok, :green, 0}

  # An enter call gets `:enter` and the previous state.
  # It may set timeouts, but it can't change state.
  def green(:enter, _previous, _crossed) do
    IO.puts("cars: green")
    :keep_state_and_data
  end

  # Someone wants to cross: switch to yellow and
  # `:postpone` the call. Postponed events come back
  # after every state change, so the same call is
  # handled again in `yellow/3`.
  def green({:call, _from}, :cross, crossed) do
    {:next_state, :yellow, crossed, [:postpone]}
  end

  def green(type, event, crossed), do: common(type, event, :green, crossed)

  # A state timeout: 30 ms after entering yellow, the
  # event `:turn_red` arrives. Leaving yellow any other
  # way would cancel it.
  def yellow(:enter, _previous, _crossed) do
    IO.puts("cars: yellow")
    {:keep_state_and_data, [{:state_timeout, 30, :turn_red}]}
  end

  def yellow(:state_timeout, :turn_red, crossed), do: {:next_state, :red, crossed}

  # Still not safe. Postpone again; the caller keeps
  # waiting inside `cross/1`.
  def yellow({:call, _from}, :cross, _crossed), do: {:keep_state_and_data, [:postpone]}
  def yellow(type, event, crossed), do: common(type, event, :yellow, crossed)

  # Red for cars. Every postponed `cross` is retried
  # here, in arrival order, and finally gets its reply.
  def red(:enter, _previous, _crossed) do
    IO.puts("cars: red")
    {:keep_state_and_data, [{:state_timeout, 50, :turn_green}]}
  end

  def red({:call, from}, :cross, crossed) do
    {:keep_state, crossed + 1, [{:reply, from, :walk}]}
  end

  def red(:state_timeout, :turn_green, crossed), do: {:next_state, :green, crossed}
  def red(type, event, crossed), do: common(type, event, :red, crossed)

  # Events every state handles the same way. With
  # `:state_functions` each state has to pass them on.
  defp common({:call, from}, :light, state, crossed) do
    {:keep_state_and_data, [{:reply, from, {state, crossed}}]}
  end
end

# Starting the machine enters the first state, so the
# enter call prints.
{:ok, crossing} = Crossing.start_link()
IO.inspect(Crossing.light(crossing), label: "light")

# Two pedestrians press the button. Both block in
# `cross/1` through yellow and get `:walk` once cars
# have red. Nobody had to keep a list of waiting
# callers, as [Backpressure](/otp/backpressure) does
# with a GenServer; the postponed calls are that list.
pedestrians = for _ <- 1..2, do: Task.async(fn -> Crossing.cross(crossing) end)
IO.inspect(Task.await_many(pedestrians), label: "pedestrians")

# Red has its own state timeout, so the light turns
# green again without anyone asking.
defmodule Wait do
  def until(check) do
    if check.(), do: :ok, else: Process.sleep(1) && until(check)
  end
end

Wait.until(fn -> match?({:green, _}, Crossing.light(crossing)) end)
IO.inspect(Crossing.light(crossing), label: "light")

# The other callback mode is `:handle_event_function`:
# every event goes to one `handle_event/4`, with the
# state as an argument. Use it when states share a lot
# of handling, or when the state isn't a plain atom.
#
# A fighting-game combo: press down, right, punch, and
# don't wait more than 50 ms between buttons. The
# state is the list of buttons still needed.
defmodule Combo do
  @behaviour :gen_statem
  @combo [:down, :right, :punch]

  def start_link, do: :gen_statem.start_link(__MODULE__, [], [])
  def press(combo, button), do: :gen_statem.call(combo, {:press, button})

  @impl true
  def callback_mode, do: :handle_event_function

  # Everything lives in the state, so the data is unused.
  @impl true
  def init([]), do: {:ok, @combo, nil}

  # The last button of the combo.
  @impl true
  def handle_event({:call, from}, {:press, button}, [button], _data) do
    {:next_state, @combo, nil, [{:reply, from, :special_move}]}
  end

  # The right button, more to go. `{:timeout, ms, msg}`
  # is an *event timeout*: any event that arrives first
  # cancels it, so it fires only after 50 ms of silence.
  def handle_event({:call, from}, {:press, button}, [button | rest], _data) do
    {:next_state, rest, nil, [{:reply, from, :ok}, {:timeout, 50, :too_slow}]}
  end

  # A wrong button at the start is ignored.
  def handle_event({:call, from}, {:press, _}, @combo, _data) do
    {:keep_state_and_data, [{:reply, from, :ok}]}
  end

  # A wrong button midway: back to the start, and
  # postpone the press, so it's tried again as the first
  # button of a new combo.
  def handle_event({:call, _from}, {:press, _}, _midway, _data) do
    {:next_state, @combo, nil, [:postpone]}
  end

  def handle_event(:timeout, :too_slow, _midway, _data), do: {:next_state, @combo, nil}
end

{:ok, combo} = Combo.start_link()
press = fn buttons -> Enum.map(buttons, &Combo.press(combo, &1)) end

IO.inspect(press.([:down, :right, :punch]), label: "combo")

# The second `:down` breaks the first attempt, but the
# postponed press starts a new one, so the combo still
# lands.
IO.inspect(press.([:down, :down, :right, :punch]), label: "combo")

# Too slow: the event timeout fires during the pause
# and the machine is back at the start before the
# punch.
first = press.([:down, :right])
Process.sleep(100)
IO.inspect(first ++ press.([:punch]), label: "too slow")

# The three timeouts, side by side:
#
# - `{:timeout, ms, msg}`: event timeout, cancelled by
#   any event.
# - `{:state_timeout, ms, msg}`: cancelled by a state
#   change.
# - `{{:timeout, name}, ms, msg}`: generic timeout,
#   lives until it fires or you set it again (to
#   `:infinity` to cancel). Several can run at once.
#
# > **Pitfall:** an event timeout is cancelled by *any*
# > event, including a harmless status query, and it
# > stays cancelled unless the handler for that event
# > sets it again. One status query in the middle of a
# > combo and the 50 ms window never closes. Use a state
# > timeout or a generic timeout when other events can
# > arrive.
#
# > **Pitfall:** postponed events wait until the state
# > changes. If it never does, they pile up in the
# > process, and the callers of postponed calls time out
# > (5 s by default for `:gen_statem.call/2`).
#
# > **Pitfall:** `@behaviour :gen_statem` doesn't define
# > `child_spec/1` the way `use GenServer` does. To put
# > the machine under a supervisor, write one:
# > `def child_spec(arg), do: %{id: __MODULE__, start:
# > {__MODULE__, :start_link, [arg]}}`.
#
# > **Pitfall:** an enter call can't change state or
# > postpone; returning `{:next_state, other, ...}` from
# > it crashes the machine. Decide the next state in
# > the event handler, and keep enter calls to side
# > effects and timeouts.
