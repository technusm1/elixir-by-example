# Every process has a small key-value store of its own,
# the *process dictionary*. Only that process can write
# to it, it's gone when the process exits, and it's
# mutable: `Process.put/2` changes it in place, with no
# new value returned. That last part is why Elixir code
# rarely uses it directly. But OTP and Elixir use it
# under the hood, and knowing it's there explains some
# surprises.
#
# The demo runs in a fresh process so the dictionary
# starts empty. `run` waits for it to finish.
run = fn fun ->
  {pid, ref} = spawn_monitor(fun)
  receive do: ({:DOWN, ^ref, :process, ^pid, _} -> :ok)
end

run.(fn ->
  IO.inspect(Process.get_keys(), label: "fresh process")

  # `put` returns the *previous* value: there's no new
  # dictionary to return, the old one was changed.
  IO.inspect(Process.put(:visits, 1), label: "first put")
  IO.inspect(Process.put(:visits, 2), label: "second put")
  IO.inspect(Process.get(:visits), label: "get")
end)

# Who uses it? `Logger.metadata/1` stores its keyword
# list there, which is why metadata set in one process
# shows up in every log line *that process* writes.
require Logger

run.(fn ->
  Logger.metadata(request_id: "req-42")
  IO.inspect(Process.get_keys(), label: "after Logger.metadata")

  # A `Task` is a new process with its own dictionary,
  # so the metadata doesn't follow. Elixir does copy one
  # thing over: `:"$callers"`, the chain of processes
  # that started the task (tools like Ecto's sandbox use
  # it to find the test that owns a connection).
  me = self()

  Task.async(fn ->
    IO.inspect(Logger.metadata(), label: "metadata in the task")
    IO.inspect(Process.get(:"$callers") == [me], label: "$callers is the parent")
  end)
  |> Task.await()
end)

# OTP keeps its own bookkeeping there too: every
# GenServer and Supervisor stores `:"$ancestors"` and
# `:"$initial_call"`. Anyone can read another process's
# dictionary with `Process.info/2`, which is how
# `:observer` shows them.
{:ok, agent} = Agent.start_link(fn -> 0 end)
{:dictionary, dict} = Process.info(agent, :dictionary)
IO.inspect(dict |> Keyword.keys() |> Enum.sort(), label: "an Agent's keys")

# > **Pitfall:** the process dictionary is hidden state.
# > A function that reads it gives different answers
# > depending on which process calls it and what ran
# > there before, so it's hard to test and easy to break
# > by moving code into a `Task`. Pass values as
# > arguments or keep them in GenServer state instead.
#
# > **Pitfall:** to keep request metadata in logs
# > written from a `Task`, copy it yourself:
# > `metadata = Logger.metadata()` before starting the
# > task, then `Logger.metadata(metadata)` inside it.
#
# > **Pitfall:** `Process.info(pid, :dictionary)` shows
# > the whole dictionary, including whatever a library
# > put there. Don't keep secrets in it.
#
# **Go deeper:** [The BEAM Book](https://blog.stenmans.org/theBeamBook/#_the_process_dictionary)
# by Erik Stenman, section 3.7, explains how the
# dictionary is stored and what it costs.
