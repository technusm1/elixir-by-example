A rolling deploy replaces the nodes of a cluster one at a time, so the service
never goes down. It also means that, for a while, **old and new versions run
side by side and talk to each other**. Every message one version sends, the
other must understand. Change a message format in one step, and the first new
node crashes the old ones it talks to.

The safe way is to change a format in two deploys, *expand then contract*:

1. **Expand.** The new version understands both the old and the new format,
   but still *sends* the old one. Roll it out everywhere.
2. **Contract.** Once every node understands the new format, a later version
   starts sending it.

On this page, a tiny app called `tally` keeps a counter on every node, and any
node can add to all of them. Version 2 adds the sending node to the message:

- `v1` sends and understands `{:add, n}`.
- `v2` understands `{:add, n}` and `{:add, n, from_node}`, and still sends
  `{:add, n}`. This is the expand step.
- `v3` sends `{:add, n, from_node}`. This is the contract step.

We first deploy `v3` straight over `v1` and watch it break, then do it
properly: `v1` to `v2` to `v3`, one node at a time.

## Three versions

Each version is its own small Mix project. Only `lib/tally.ex` changes.

```file v1/mix.exs
```

```file v1/lib/tally.ex
```

```file v2/mix.exs
```

`v2` adds a clause for the new format and keeps sending the old one.

```file v2/lib/tally.ex
```

```file v3/mix.exs
```

`v3` changes one line: the message it sends.

```file v3/lib/tally.ex
```

## Build all three

```sh
for v in v1 v2 v3; do (cd $v && MIX_ENV=prod mix release --quiet); done
```

Two shell functions keep the commands short: `tally v1 a ...` runs the `v1`
release as node `tally_a`, `start` starts a node and waits until it's up, and
`halt` stops one and waits until it's gone.

```sh
export RELEASE_COOKIE=tally-demo-cookie

tally() { v=$1; n=$2; shift 2; RELEASE_NODE="tally_$n" "$v/_build/prod/rel/tally/bin/tally" "$@"; }
start() { tally "$1" "$2" daemon; until tally "$1" "$2" pid > /dev/null 2>&1; do sleep 0.1; done; }
halt() { tally "$1" "$2" stop; while tally "$1" "$2" pid > /dev/null 2>&1; do sleep 0.1; done; }
```

## Version 1 in production

Two nodes on `v1`, connected. Adding from `a` reaches both.

```sh
start v1 a
start v1 b
tally v1 a rpc 'Tally.join(:tally_b)'
tally v1 a rpc 'IO.inspect(Tally.add_everywhere(1))'
```

## The wrong way: v3 straight over v1

Replace `b` with `v3`. Its messages use the new format, `a` has no clause for
it, and `a`'s counter process crashes (its supervisor restarts it, with the
count lost).

```sh
halt v1 b
start v3 b
tally v3 b rpc 'Tally.join(:tally_a)'
tally v3 b rpc 'IO.inspect(Tally.add_everywhere(1))'
```

## The right way: expand, then contract

Roll back `b`, this time to `v2`. Mixed `v1`/`v2` is safe in both directions:
both send the old format, and both understand it.

```sh
halt v3 b
start v2 b
tally v2 b rpc 'Tally.join(:tally_a)'
tally v2 b rpc 'IO.inspect(Tally.add_everywhere(1))'
tally v1 a rpc 'IO.inspect(Tally.add_everywhere(1))'
```

Finish the expand step by moving `a` to `v2` as well. Now every node
understands the new format.

```sh
halt v1 a
start v2 a
tally v2 a rpc 'Tally.join(:tally_b)'
```

Now the contract step can roll out. While it does, `v3` nodes send the new
format to `v2` nodes, which understand it.

```sh
halt v2 b
start v3 b
tally v3 b rpc 'Tally.join(:tally_a)'
tally v3 b rpc 'IO.inspect(Tally.add_everywhere(1))'
halt v2 a
start v3 a
tally v3 a rpc 'Tally.join(:tally_b)'
tally v3 a rpc 'IO.inspect(Tally.add_everywhere(1))'
```

```sh
halt v3 a
halt v3 b
```

> **Pitfall:** "messages" means everything that crosses between nodes:
> `GenServer` calls and casts, `:pg` and `:global` traffic, `:erpc` calls to
> functions the old version doesn't have yet (they fail with
> `UndefinedFunctionError`), and terms stored in Mnesia or ETS tables that
> both versions read.

> **Pitfall:** the same rule holds for data you store, and for longer: a
> database column or a persisted term must be readable by every version that
> might still be running, and by the version you might roll back to.

> **Pitfall:** a rollback is a deploy too. If `v3` must be rolled back to `v1`
> while some nodes already send the new format, `v1` breaks the same way. Roll
> back one step at a time, to `v2`.

> **Pitfall:** the BEAM can also swap code inside a running node without a
> restart (hot code upgrades with appups). It's powerful but demanding, and
> most teams use rolling restarts like these. Hot code loading gets its own
> page in the Production track.
