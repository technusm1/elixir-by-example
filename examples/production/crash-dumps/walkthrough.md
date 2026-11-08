When a BEAM node dies on its own, it usually leaves a note behind: a *crash
dump*, a plain-text file describing every process, its mailbox, what it was
running, and how memory was used at the moment of death. The node is gone,
but the dump often tells you why.

The node writes one when:

- it runs out of memory (the first line says something like
  `eheap_alloc: Cannot allocate 1234 bytes of memory`),
- `:erlang.halt/1` is called with a string,
- the boot fails (`init terminating in do_boot`),
- it receives the `SIGUSR1` signal, which is how you get a dump of a node
  that is still running but not answering anything.

This page uses the last one. A small script starts a worker that never
handles its messages and floods it with 50,000 jobs. Then we ask the node for
a dump and read it.

## A stuck node

```file stuck.exs
```

`ERL_CRASH_DUMP` sets where the dump goes. Without it, the node writes
`erl_crash.dump` into its working directory. Start the script in the
background and wait until it has written its OS process id.

```sh
export ERL_CRASH_DUMP=crash.dump
elixir stuck.exs &
until [ -s node.pid ]; do sleep 0.1; done
```

## Ask for a dump

`SIGUSR1` makes the node write the dump and then stop. It's a last resort,
for a node so stuck that you can't connect a remote shell to it, but it
records the state you need before you restart.

```sh
kill -USR1 "$(cat node.pid)"
wait $! || echo "the node exited with status $?"
```

## Read it

The dump is text, divided into sections that start with `=`. The first lines
say why the node died: the *slogan*.

```sh
grep '^Slogan' crash.dump
```

Each `=proc:` section is one process. With thousands of processes, the quick
win is to list only the ones with messages waiting: here that's the worker.
Its program counter says which function it was in, written the Erlang way:
`'Elixir.Stuck':wait/0` is `Stuck.wait/0`. In a real incident, that's the
code to read first.

```sh
awk '
  /^=proc:/                 { name = "(no name)"; queue = 0 }
  /^Name: /                 { name = $2 }
  /^Message queue length: / { queue = $4 }
  /^Program counter: /      { if (queue > 0) {
                                sub(/.*\(/, ""); sub(/ \+.*/, "")
                                print name, queue, $0 } }
' crash.dump
```

Other sections worth a look: `=memory` (where memory went: processes,
binaries, ETS, code), `=ets` (each table's size), and `=proc_messages`
(the first messages in each mailbox, which often name the sender).

For browsing a dump, OTP ships a viewer: `:crashdump_viewer.start(~c"crash.dump")`
from `iex` opens it in a window (it needs Erlang built with wxWidgets).

> **Pitfall:** a container's filesystem disappears with the container, and
> the dump with it. Point `ERL_CRASH_DUMP` at a mounted volume (in a release,
> export it in `rel/env.sh.eex`), or the evidence is gone by the time you
> look.

> **Pitfall:** a node killed from the outside leaves no dump. Kubernetes'
> `OOMKilled` and the Linux OOM killer send `SIGKILL`, which the BEAM can't
> catch. The BEAM has no setting for "use at most this much memory", so if
> pods die with `OOMKilled`, find the growth before the kernel does: watch
> `:erlang.memory/0`, cap single processes with the `:max_heap_size` process
> flag, and look for full mailboxes (see [Mailboxes](/production/mailboxes)).

> **Pitfall:** with `heart` enabled (it restarts a node that dies), no dump
> is written at all unless `ERL_CRASH_DUMP_SECONDS` is set. Set it to the
> number of seconds the node may spend writing the dump, or `-1` to wait
> until it's complete. A dump of a big node takes time and disk space.

**Go deeper:** section 18.7 of [The BEAM Book](https://blog.stenmans.org/theBeamBook/#_crash_dumps_in_erlang)
by Erik Stenman walks through the sections of a crash dump in detail.
