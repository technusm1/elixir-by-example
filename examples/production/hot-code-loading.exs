# The BEAM can replace a module's code while the system
# runs, without stopping a single process. That's how a
# remote shell can patch a bug in production, and how
# `iex -S mix` recompiles as you edit. It's also easy to
# get wrong, because *which* version a process runs
# depends on how it calls its own functions.
#
# The rules:
#
# 1. A module can have two versions loaded at once:
#    *current* and *old*. Loading a new version makes the
#    current one old.
# 2. A process keeps running the version it's in until
#    it makes a *fully qualified* call (`Module.fun()`),
#    which always goes to the current version. A *local*
#    call (`fun()`) stays in the version it's in.
# 3. Loading a third version needs the old one gone first.
#    Purging it kills every process still running it.
#
# The demo runs two looping processes on version 1, loads
# version 2, and watches one move to it and the other
# stay behind; then it purges the old version.
#
# Redefining a module in a script normally warns; this
# page does it on purpose, so the warning is switched off.
Code.put_compiler_option(:ignore_module_conflict, true)

# Version 1. Both loops answer `{:ask, from}` with
# `hello/0`. `local_loop/0` loops with a local call;
# `remote_loop/0` loops with a fully qualified one.
defmodule Greeting do
  def hello, do: "v1"

  def local_loop do
    receive do
      {:ask, from} ->
        send(from, hello())
        local_loop()
    end
  end

  def remote_loop do
    receive do
      {:ask, from} ->
        send(from, hello())
        __MODULE__.remote_loop()
    end
  end
end

local = spawn(&Greeting.local_loop/0)
remote = spawn(&Greeting.remote_loop/0)

ask = fn pid ->
  send(pid, {:ask, self()})

  receive do
    answer -> answer
  end
end

IO.inspect({ask.(local), ask.(remote)}, label: "before the upgrade")

# Version 2. Defining the module again compiles it and
# loads it while both processes wait in `receive`. Each
# is still inside version 1's code.
defmodule Greeting do
  def hello, do: "v2"

  def local_loop do
    receive do
      {:ask, from} ->
        send(from, hello())
        local_loop()
    end
  end

  def remote_loop do
    receive do
      {:ask, from} ->
        send(from, hello())
        __MODULE__.remote_loop()
    end
  end
end

# The first answer from each comes from version 1: the
# `receive` that got the message was v1 code. After it,
# `remote_loop` calls `Greeting.remote_loop()` and jumps
# to version 2; `local_loop` calls `local_loop()` and
# stays in version 1 for good.
IO.inspect({ask.(local), ask.(remote)}, label: "first ask after")
IO.inspect({ask.(local), ask.(remote)}, label: "second ask after")

# Version 1 is now *old* code, and `local` still runs it.
# `:code.soft_purge/1` removes old code only if no
# process uses it, so it refuses. `:code.purge/1` removes
# it anyway, killing every process still running it.
IO.inspect(:code.soft_purge(Greeting), label: "soft purge")
IO.inspect(:code.purge(Greeting), label: "purge")
IO.inspect({Process.alive?(local), Process.alive?(remote)}, label: "alive (local, remote)")

# > **Pitfall:** a long-running process must reach a
# > fully qualified call regularly, or an upgrade leaves
# > it behind and the *next* upgrade kills it.
#
# ## GenServers, Agents and other OTP processes
#
# OTP behaviours never get left behind. A `GenServer`'s
# receive loop lives in `:gen_server`, not in your
# module, and it calls your callbacks fully qualified
# (`Counter.handle_call(...)`). So the next message after
# a load runs the new callbacks. The state isn't touched:
# it's data the process holds, not part of the code.
# `Agent`, `Task.Supervisor`, `Supervisor` and
# `:gen_statem` work the same way.
#
# Two counters, so we can later migrate one and not the
# other. A crash in the unmigrated one is part of the
# demo, so the crash report is silenced.
Logger.configure(level: :none)

defmodule Counter do
  use GenServer

  def init(n), do: {:ok, n}
  def handle_call(:bump, _from, n), do: {:reply, n + 1, n + 1}
  def handle_call(:peek, _from, n), do: {:reply, n, n}
end

{:ok, a} = GenServer.start(Counter, 0)
{:ok, b} = GenServer.start(Counter, 0)
for pid <- [a, b], _ <- 1..2, do: GenServer.call(pid, :bump)
IO.inspect(GenServer.call(a, :peek), label: "v1 peek")

# Version 2 changes what the callbacks return, but the
# state is still a plain integer.
defmodule Counter do
  use GenServer

  def init(n), do: {:ok, n}
  def handle_call(:bump, _from, n), do: {:reply, n + 10, n + 10}
  def handle_call(:peek, _from, n), do: {:reply, {:count, n}, n}
end

# The count survived (2), and the very next call already
# ran version 2's code. No process is inside version 1's
# code, so a soft purge succeeds: nobody gets killed.
IO.inspect(GenServer.call(a, :peek), label: "v2 peek")
IO.inspect(:code.soft_purge(Counter), label: "soft purge")

# Version 3 changes the *shape* of the state: a map
# instead of an integer. Loading it doesn't change the
# integers both processes hold, so the new callbacks get
# state they don't understand. `:sys` is OTP's module
# for reaching into any OTP process (GenServer, Agent,
# Supervisor...) from outside: `:sys.get_state/1`
# returns its current state without going through its
# callbacks.
defmodule Counter do
  use GenServer

  def init(n), do: {:ok, %{count: n, bumps: 0}}

  def handle_call(:bump, _from, s) do
    {:reply, s.count + 1, %{s | count: s.count + 1, bumps: s.bumps + 1}}
  end

  def handle_call(:peek, _from, s), do: {:reply, s, s}

  # Turns the old state into the new shape. OTP calls it
  # only when asked to (below), never on load.
  def code_change(_old_vsn, n, _extra) when is_integer(n) do
    {:ok, %{count: n, bumps: 0}}
  end
end

IO.inspect(:sys.get_state(b), label: "b's state after load")

# When the server crashes during a call, the caller
# exits with `{reason, {GenServer, :call, args}}`, and
# a crash in a callback makes the reason an
# `{error, stacktrace}` pair. Here the error is
# `{:badmap, 2}`: `s.count` on the integer 2.

try do
  GenServer.call(b, :bump)
catch
  :exit, {{reason, _stack}, _call} -> IO.inspect(reason, label: "b crashed")
end

# For `a`, we migrate first. `:sys.suspend/1` stops it
# handling messages (callers wait), `:sys.change_code/4`
# runs `code_change/3` inside the process, and
# `:sys.resume/1` lets it carry on with the new state.
:ok = :sys.suspend(a)
IO.inspect(:sys.change_code(a, Counter, :v2, nil), label: "change_code")
:ok = :sys.resume(a)

IO.inspect(GenServer.call(a, :bump), label: "a bump")
IO.inspect(GenServer.call(a, :peek), label: "a peek")

# This suspend, load, change_code, resume dance is what a
# release *upgrade* does for every process whose child
# spec lists the module under `modules:`, following an
# *appup* file: per application, the steps from one
# version to the next.
# Most teams skip it: they keep the state shape
# compatible, or roll out new nodes and let processes
# restart with fresh state (see
# [Rolling Deploys](/deployment/rolling-deploys)).
#
# > **Pitfall:** `use GenServer` defines a default
# > `code_change/3` that returns the state unchanged. If
# > you change the state shape and forget to write your
# > own, a release upgrade "succeeds" and the process
# > crashes on its next message, like `b` did.
#
# > **Pitfall:** an anonymous function remembers the
# > version of the module that created it. Keeping one
# > in state (or in ETS) pins that old version, and a
# > purge kills whoever calls it. This is the trap with
# > `Agent`, whose state is often built from closures:
# > `Agent.update(pid, fn s -> ... end)` runs the fun
# > and forgets it, which is fine, but storing a fun
# > *in* the state isn't. Store `&Mod.fun/arity` captures
# > or `{Mod, :fun, args}` tuples instead.
#
# **Go deeper:** chapter 8 of [The BEAM Book](https://blog.stenmans.org/theBeamBook/#CH-Calls)
# by Erik Stenman, "Different Types of Calls, Linking and
# Hot Code Loading", shows what local, remote and closure
# calls compile to, and why that decides which version
# runs.
