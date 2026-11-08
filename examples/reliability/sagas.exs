# Booking a trip takes a flight, a hotel and a car, from
# three different services, each with its own database.
# There's no transaction that spans all three. If the
# car is sold out after the flight and hotel are booked,
# nothing rolls those back for you.
#
# A *saga* does it by hand. Each step comes with a
# *compensation*, an action that undoes its effect
# (cancel the flight, cancel the hotel). The steps run
# in order. If one fails, the compensations of the
# steps that already succeeded run in reverse order,
# and the system ends up where it started.
#
# The three services, as one Agent holding everything
# booked. `sold_out` lists what can't be booked, and
# `flaky` lists cancellations that fail on the first try.
defmodule Travel do
  def start(opts \\ []) do
    Agent.start_link(fn ->
      %{booked: [], sold_out: opts[:sold_out] || [], flaky: opts[:flaky] || []}
    end)
  end

  def book(travel, kind, what) do
    Agent.get_and_update(travel, fn state ->
      if kind in state.sold_out do
        {{:error, :sold_out}, state}
      else
        booking = {kind, what}
        {{:ok, booking}, %{state | booked: state.booked ++ [booking]}}
      end
    end)
  end

  def cancel(travel, {kind, _} = booking) do
    Agent.get_and_update(travel, fn state ->
      if kind in state.flaky do
        {{:error, :timeout}, %{state | flaky: List.delete(state.flaky, kind)}}
      else
        {:ok, %{state | booked: List.delete(state.booked, booking)}}
      end
    end)
  end

  def booked(travel), do: Agent.get(travel, & &1.booked)
end

# The saga runner. A step is a name, an action returning
# `{:ok, result}` or `{:error, reason}`, and a
# compensation that receives the action's result.
defmodule Saga do
  def run(steps) do
    result =
      Enum.reduce_while(steps, [], fn {name, action, compensate}, done ->
        case action.() do
          {:ok, result} ->
            IO.puts("  #{name}: ok")
            {:cont, [{name, compensate, result} | done]}

          {:error, reason} ->
            IO.puts("  #{name}: failed (#{inspect(reason)})")
            {:halt, {:failed, name, reason, done}}
        end
      end)

    case result do
      {:failed, name, reason, done} ->
        # `done` is newest first: exactly the order to undo.
        Enum.each(done, &compensate/1)
        {:error, name, reason}

      _done ->
        :ok
    end
  end

  # A compensation must not be skipped: a half-cancelled
  # trip is the thing the saga exists to prevent. So it's
  # retried until it works.
  defp compensate({name, compensate, result} = step) do
    case compensate.(result) do
      :ok ->
        IO.puts("  undo #{name}: ok")

      {:error, reason} ->
        IO.puts("  undo #{name}: failed (#{inspect(reason)}), retrying")
        compensate(step)
    end
  end
end

trip = fn travel ->
  [
    {:flight, fn -> Travel.book(travel, :flight, "LIS-OSL") end, &Travel.cancel(travel, &1)},
    {:hotel, fn -> Travel.book(travel, :hotel, "Oslo, 3 nights") end, &Travel.cancel(travel, &1)},
    {:car, fn -> Travel.book(travel, :car, "compact") end, &Travel.cancel(travel, &1)}
  ]
end

# Everything available: all three steps succeed.
{:ok, travel} = Travel.start()
IO.puts("trip 1")
IO.inspect(Saga.run(trip.(travel)), label: "  result")
IO.inspect(Travel.booked(travel), label: "  booked")

# No cars left. The car step fails, the hotel and the
# flight are cancelled, newest first, and nothing stays
# booked.
{:ok, travel} = Travel.start(sold_out: [:car])
IO.puts("trip 2")
IO.inspect(Saga.run(trip.(travel)), label: "  result")
IO.inspect(Travel.booked(travel), label: "  booked")

# The hotel's cancellation times out once. The runner
# retries it, and the trip still ends fully undone.
{:ok, travel} = Travel.start(sold_out: [:car], flaky: [:hotel])
IO.puts("trip 3")
IO.inspect(Saga.run(trip.(travel)), label: "  result")
IO.inspect(Travel.booked(travel), label: "  booked")

# > **Pitfall:** this runner keeps its progress in memory.
# > If the node stops halfway, nobody knows a flight was
# > booked and needs cancelling. A real saga writes each
# > step to a database before and after doing it (a
# > *saga log*), and on restart finishes or undoes
# > whatever was in progress. A job queue that persists
# > its jobs, like [Oban](https://hexdocs.pm/oban), is a
# > common way to drive one.
#
# > **Pitfall:** retried compensations, and retried
# > steps after a restart, can run twice. Both must be
# > idempotent: cancelling a cancelled booking is fine,
# > refunding a refunded payment isn't. See
# > [Idempotency and Retries](/distributed/idempotency).
#
# > **Pitfall:** a saga isn't isolated like a
# > transaction. Between booking and cancelling, other
# > people can see the hotel room as taken. And some
# > actions can't be undone at all: an email already sent
# > stays sent. Put steps like that last, after
# > everything that can fail.
