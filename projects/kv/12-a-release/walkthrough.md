Up to now KV lived inside scripts that started their own nodes. Deployed, it's
a Mix project built into a release, and every server runs the *same* build.
What differs per server (its node name, the cookie, which nodes to cluster
with) comes from the environment at boot, through `config/runtime.exs`.

On this page:

1. KV as a Mix project: the replicated store from step 8, `:pg` and
   libcluster, all started by the application's supervisor.
2. One release, built once.
3. Started twice, as nodes `kv_a` and `kv_b`, with different environment
   variables. The nodes find each other through libcluster and replicate
   writes.

## The project

libcluster is the only dependency, declared in `deps` and fetched from Hex as
on [Mix Projects](/core/mix).

```file mix.exs
```

The node list is configuration like any other, so it comes from the
environment, in `runtime.exs`.

```file config/runtime.exs
```

The supervisor starts `:pg` (the replicas find each other through it), then
libcluster, then this node's replica. `:pg` is an Erlang module without a
`child_spec/1`, so its child spec is written out as a map: an `id` and the
`{module, function, args}` that starts it (see
[Applications and Configuration](/otp/applications)).

```file lib/kv/application.ex
```

The replica is step 8's, plus `count/0`, which we use to tell when both nodes
can see each other.

```file lib/kv/replica.ex
```

## Build once

`mix deps.get` prints how long dependency resolution took, which changes on
every run, so its output is silenced here.

```sh
mix deps.get > /dev/null
MIX_ENV=prod mix release --quiet
```

## Start two nodes from the same build

Settings shared by every node go in the environment once. `RELEASE_NODE` with
`RELEASE_DISTRIBUTION=name` gives a node its full name, and `RELEASE_COOKIE`
replaces the random cookie the build generated, so both nodes share one. The
`kv` shell function runs the release's script as node `kv_a` or `kv_b`.

```sh
export RELEASE_DISTRIBUTION=name
export RELEASE_COOKIE=kv-demo-cookie
export CLUSTER_NODES=kv_a@127.0.0.1,kv_b@127.0.0.1

kv() { node=$1; shift; RELEASE_NODE="kv_$node@127.0.0.1" _build/prod/rel/kv/bin/kv "$@"; }

kv a daemon
kv b daemon
```

Both nodes boot, and libcluster connects them in the background. We wait until
each node sees both replicas.

```sh
until [ "$(kv a rpc 'IO.write(KV.Replica.count())' 2>/dev/null)" = 2 ] &&
  [ "$(kv b rpc 'IO.write(KV.Replica.count())' 2>/dev/null)" = 2 ]; do
  sleep 0.2
done
kv a rpc 'IO.inspect(Node.list(), label: "a is connected to")'
```

## One store

A write on `kv_a`, read on `kv_b`: two copies of the same build, configured
only by their environment, acting as one store.

```sh
kv a rpc 'KV.Replica.put("lang", "elixir")'
kv b rpc 'IO.inspect(KV.Replica.get("lang"), label: "b reads lang")'
```

```sh
kv a stop
kv b stop
```

> **Pitfall:** `String.to_atom/1` on configuration you control is fine; on
> anything a user can send, it isn't (atoms are never garbage collected, and
> the atom table has a limit).

The store still forgets everything when both nodes stop, and new nodes start
empty (steps 9 and 10 showed the fixes). The next steps put this release in a
container and run it on Kubernetes.
