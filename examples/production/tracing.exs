# Something in production returns the wrong number. The
# logs don't say why, and adding `IO.inspect` means a new
# build and a deploy, after which the problem may be gone.
# On the BEAM you can ask the running system instead:
# *tracing* makes the VM report, as messages, every call a
# chosen process makes to chosen functions, with the
# arguments and return values. No code changes, no
# restart, and it's off again when you're done.
#
# The demo:
#
# 1. A worker process computes an order total with a
#    small `Pricing` module.
# 2. We trace every call it makes into `Pricing`, private
#    functions included, with return values.
# 3. We narrow the trace with a match specification, so
#    only the calls we care about are reported.
#
# Traces are organised in *sessions* (`:trace`, OTP 27
# and later): each session has its own tracer and its own
# settings, so several people, or tools, can trace the
# same system without disturbing each other.
defmodule Pricing do
  def total(items), do: items |> Enum.map(&line/1) |> Enum.sum() |> with_tax()

  defp line({qty, price}), do: qty * price
  defp with_tax(sum), do: round(sum * 1.2)
end

# A process that waits for an order, prices it, and
# replies. It stands in for a request handler.
start_worker = fn ->
  spawn(fn ->
    receive do
      {:price, items, from} -> send(from, {:total, Pricing.total(items)})
    end
  end)
end

# Trace events arrive as messages to the tracer, here this
# script's process. `:trace.delivered/2` makes sure every
# event the worker caused has arrived before we read them.
# `show/1` prints calls indented by depth, without pids
# (they change on every run).
show = fn session, worker ->
  ref = :trace.delivered(session, worker)

  receive do
    {:trace_delivered, ^worker, ^ref} -> :ok
  end

  collect = fn again, depth ->
    receive do
      {:trace, ^worker, :call, {m, f, args}} ->
        call = "#{inspect(m)}.#{f}(#{Enum.map_join(args, ", ", &inspect/1)})"
        IO.puts(String.duplicate("  ", depth) <> call)
        again.(again, depth + 1)

      {:trace, ^worker, :return_from, {_m, _f, _arity}, value} ->
        IO.puts(String.duplicate("  ", depth - 1) <> "=> " <> inspect(value))
        again.(again, depth - 1)
    after
      0 -> :ok
    end
  end

  collect.(collect, 0)
end

order = [{2, 10}, {1, 5}]

# Step 2. A session with this process as the tracer. Mark
# the worker for call tracing, then pick the functions:
# every function in `Pricing` (`:_` matches any name and
# arity), with `:local` so private functions count too.
# The match specification `[{:_, [], [{:return_trace}]}]`
# means "any arguments, no conditions, and also report
# the return value".
session = :trace.session_create(:pricing, self(), [])
worker = start_worker.()
:trace.process(session, worker, true, [:call])
:trace.function(session, {Pricing, :_, :_}, [{:_, [], [{:return_trace}]}], [:local])

send(worker, {:price, order, self()})
receive do: ({:total, total} -> IO.inspect(total, label: "total"))
show.(session, worker)

# Step 3. A match specification can also filter. This one
# traces `line/1` only when the quantity (`:"$1"`, the
# first element of the argument tuple) is above 1:
# head `[{:"$1", :_}]`, guard `[{:>, :"$1", 1}]`.
:trace.function(session, {Pricing, :_, :_}, false, [:local])
worker = start_worker.()
:trace.process(session, worker, true, [:call])

:trace.function(
  session,
  {Pricing, :line, 1},
  [{[{:"$1", :_}], [{:>, :"$1", 1}], [{:return_trace}]}],
  [:local]
)

send(worker, {:price, order, self()})
receive do: ({:total, total} -> IO.inspect(total, label: "total"))
show.(session, worker)

# Destroying the session turns off everything it enabled.
:trace.session_destroy(session)

# > **Pitfall:** every traced call becomes a message. On a
# > busy production node, tracing a hot function without
# > limits floods the tracer and can take the node down.
# > Trace narrowly (one process, one function, a match
# > spec), and use a tool that stops after N messages or
# > a rate, such as `recon_trace` from the `recon` library.
#
# > **Pitfall:** `:return_trace` is not free: it keeps the
# > traced call from being a tail call, so a traced
# > recursive loop grows its stack. Trace loops briefly.
#
# > **Pitfall:** match specifications are terms, not
# > Elixir code: `:"$1"` binds a value, guards are
# > tuples like `{:>, :"$1", 1}`. The `ex2ms` library
# > lets you write them as Elixir functions.
#
# **Go deeper:** chapter 19 of [The BEAM Book](https://blog.stenmans.org/theBeamBook/#CH-Tracing)
# by Erik Stenman covers the built-in trace flags, match
# specifications and third-party tracing tools.
