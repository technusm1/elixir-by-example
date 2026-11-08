A user reports that KV ignores updates: they set a key, set it again, and
still read the first value. The node is running in production. You could add
logging, build, deploy and wait for it to happen again. On the BEAM you can
instead look inside the running node, find the bug, and fix it there, without
a restart and without losing the data in memory.

This step runs KV with that bug and fixes it live:

1. **Reproduce** the report against the running node with `rpc`.
2. **Look at the state** of the replica process with `:sys.get_state/1`.
3. **Trace** the replica while one update happens, to see what it receives
   and what it does with it.
4. **Patch** the running code: compile the fixed module into the node. The
   replica keeps its state and starts using the new code at once.

## The project

KV from step 12, with one line changed: `handle_call/3` for `:put` uses
`Map.put_new/3`, which only adds keys that aren't there yet. That's the bug.

```file mix.exs
```

```file mix.lock
```

```file config/runtime.exs
```

```file lib/kv/application.ex
```

```file lib/kv/replica.ex
```

## Start it

One node is enough. As in step 12, the environment names it; here the cluster
is just itself.

```sh
mix deps.get > /dev/null
MIX_ENV=prod mix release --quiet > /dev/null
export RELEASE_DISTRIBUTION=name RELEASE_NODE=kv_live@127.0.0.1 CLUSTER_NODES=kv_live@127.0.0.1
kv() { _build/prod/rel/kv/bin/kv "$@"; }
kv daemon
until kv pid > /dev/null 2>&1; do sleep 0.1; done
```

## 1. Reproduce

```sh
kv rpc 'KV.Replica.put("lang", "elixir")'
kv rpc 'KV.Replica.put("lang", "erlang")'
kv rpc 'IO.inspect(KV.Replica.get("lang"), label: "lang")'
```

## 2. Look at the state

`:sys.get_state/1` asks any OTP process (GenServer, Agent, Supervisor...) for
its current state. The replica holds the old value, so `get` isn't the
problem: the update never landed.

```sh
kv rpc 'IO.inspect(:sys.get_state(KV.Replica), label: "replica state")'
```

## 3. Trace one update

A small script, run inside the node with `Code.eval_file/1`, traces the
replica's `handle_call/3` (see Tracing) while it makes one `put`, and prints
what came in and what state went out.

```file debug/trace_put.exs
```

```sh
kv rpc 'Code.eval_file("debug/trace_put.exs")'
```

The message arrives with the new value, and the state comes back unchanged.
The bug is in the `:put` clause of `handle_call/3`: `Map.put_new/3` should be
`Map.put/3`.

## 4. Patch the running node

The fix is one line, in a copy of the module:

```file patch/replica.ex
```

Compiling that file inside the node loads the new version of `KV.Replica`
(see Hot Code Loading). The replica is a GenServer, and OTP's loop calls
`handle_call/3` with a fully qualified call, so the very next request runs the
new code. The state, with every key in it, is untouched. Redefining a module
normally warns; here it's the point, so the warning is switched off.

```sh
kv rpc 'Code.put_compiler_option(:ignore_module_conflict, true); Code.compile_file("patch/replica.ex")'
kv rpc 'KV.Replica.put("lang", "erlang")'
kv rpc 'IO.inspect(KV.Replica.get("lang"), label: "lang")'
```

```sh
kv stop
```

> **Pitfall:** a live patch exists only in that node's memory. A restart, a
> new pod, or the next deploy brings the bug back. Treat it as first aid: put
> the same fix in the code, build a release and deploy it.

> **Pitfall:** `rpc` and `remote` give whoever runs them full control of the
> node, the same power that fixed this bug. Guard that access as carefully as
> production database credentials.

> **Pitfall:** `:sys.get_state/1` copies the whole state to the caller, and
> waits for the process to answer. On a process with a huge state, or one
> that is stuck, it can be slow or time out. Ask for what you need, and give
> it a timeout (`:sys.get_state(pid, 1_000)`).

**Go deeper:** [The BEAM Book](https://blog.stenmans.org/theBeamBook/#CH-Debugging) by Erik Stenman has chapters
on debugging ([18](https://blog.stenmans.org/theBeamBook/#CH-Debugging)), tracing ([19](https://blog.stenmans.org/theBeamBook/#CH-Tracing)) and
connecting to a live system ([17](https://blog.stenmans.org/theBeamBook/#CH-Ops)).
