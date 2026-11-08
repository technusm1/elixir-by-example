# Tracing tells you *what* a process calls. A profiler
# tells you *where the cost goes*: how many times each
# function ran, how long it took, or how much memory it
# allocated. Erlang/OTP ships `:tprof` (OTP 27+), which
# replaces the older `:eprof` and `:cprof` with one
# tool. It measures one of three things:
#
# - `:call_count`: calls per function, the cheapest.
# - `:call_time`: time per function, the usual choice.
# - `:call_memory`: words allocated per function.
#
# Time changes on every run, so this page uses counts
# and memory, which don't. The code under test builds a
# report by appending to a list, a common mistake.
defmodule Report do
  def slow(items), do: Enum.reduce(items, [], fn x, acc -> acc ++ [x * 2] end)

  def fast(items) do
    items
    |> Enum.reduce([], fn x, acc -> [x * 2 | acc] end)
    |> Enum.reverse()
  end
end

# `:tprof.profile/2` runs a function with profiling on.
# By default it prints a table that includes pids;
# `report: :return` hands back the data instead, so we
# can print the rows our own way: busiest function last.
profile = fn label, fun ->
  {_result, {:call_memory, rows}} =
    :tprof.profile(fun, %{type: :call_memory, report: :return})

  IO.puts(label)

  rows
  |> Enum.map(fn {mod, fun, arity, per_process} ->
    calls = per_process |> Enum.map(&elem(&1, 1)) |> Enum.sum()
    words = per_process |> Enum.map(&elem(&1, 2)) |> Enum.sum()
    {Exception.format_mfa(mod, fun, arity), calls, words}
  end)
  |> Enum.sort_by(fn {_name, _calls, words} -> words end)
  |> Enum.each(fn {name, calls, words} ->
    IO.puts("  #{String.pad_trailing(name, 36)} calls: #{calls}, words: #{words}")
  end)
end

items = Enum.to_list(1..200)
profile.("slow, 200 items:", fn -> Report.slow(items) end)

# Almost all the memory goes to `++`. Appending copies
# the whole left-hand list every time, so the 200th call
# copies 199 elements. Double the input and the cost
# quadruples: the work is quadratic.
more = Enum.to_list(1..400)
profile.("slow, 400 items:", fn -> Report.slow(more) end)

# Prepending allocates one list cell (2 words) and copies
# nothing, and one `Enum.reverse/1` at the end puts the
# order back.
profile.("fast, 200 items:", fn -> Report.fast(items) end)

# In a project you don't need to write any of this:
# `mix profile.tprof -e "Report.slow(Enum.to_list(1..200))"`
# prints the same tables (`--type calls|time|memory`).
#
# On a live node, the same API takes a running process
# instead of a function: `:tprof.start/0`, then
# `:tprof.enable_trace/1` with the pids or
# `:processes`, `:tprof.set_pattern/3` for the modules,
# and `:tprof.collect/0` after a few seconds.
#
# > **Pitfall:** `:call_time` and `:call_memory` slow the
# > profiled code down a lot, and profiling every
# > process makes the whole node slower. On a production
# > node, profile one process or one module, for a few
# > seconds, and start with `:call_count`.
#
# > **Pitfall:** a profiler shows where *one process*
# > spends its time. If the node is slow because work
# > waits in a mailbox or a run queue, the profile looks
# > fine. Check `message_queue_len` and reductions first
# > (see [Mailboxes](/production/mailboxes) and
# > [Schedulers and Reductions](/production/schedulers)).
#
# > **Pitfall:** don't trust a micro-benchmark from
# > a script or `iex`: code evaluated there isn't
# > compiled the same way as a module. Profile functions
# > in compiled modules, as here, and use a benchmarking
# > library like `benchee` for timings.
#
# **Go deeper:** chapter 21 of [The BEAM Book](https://blog.stenmans.org/theBeamBook/#CH-Profiling)
# by Erik Stenman, "Profiling, Monitoring, and
# Performance Optimization", compares the profiling
# tools and what each costs.
