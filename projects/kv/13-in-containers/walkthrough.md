Step 12 started two KV nodes from one release, on one machine, configured only
by environment variables. This step does the same with containers: one image,
two containers, each told who it is by its environment. It's the shape KV will
have on Kubernetes in the next step, small enough to run on a laptop with
Docker Compose.

On this page:

1. KV from step 12, plus a `mix.lock` that pins its dependencies.
2. A `Dockerfile` built like the one on the Containers page.
3. A `compose.yaml` that starts two containers from that image and gives
   each a node name.
4. Start the cluster, write on one node, read on the other.

## The project

Unchanged from step 12, except for the lock file. `mix deps.get` writes it the
first time; commit it, so every image is built with exactly the versions you
tested.

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

## The image

```file Dockerfile
```

```file .dockerignore
```

## Two nodes, one image

A node name has two parts, `name@host`. With `RELEASE_DISTRIBUTION=sname` the
host part is the machine's short hostname, here the container's hostname.
Compose names each container's network address after its service, so `kv-a`
and `kv-b` resolve inside the network and `kv@kv-a` can reach `kv@kv-b`.

```file compose.yaml
```

## Run it

```sh
docker compose up -d --build
```

Wait until node `kv-a` sees both replicas, then write there and read on `kv-b`.
`docker compose exec` runs the release script inside a container, with that
container's environment, so `rpc` talks to the node running there.

```sh
until docker compose exec kv-a bin/kv rpc 'IO.write(KV.Replica.count())' 2>/dev/null | grep -q 2; do
  sleep 0.5
done
docker compose exec kv-a bin/kv rpc 'KV.Replica.put("lang", "elixir")'
docker compose exec kv-b bin/kv rpc 'IO.inspect(KV.Replica.get("lang"))'
```

```sh
docker compose down
```

> **Pitfall:** Erlang distribution needs more than one port between nodes:
> EPMD on 4369 and a port for each node. Inside one Compose network every
> port is open; across hosts or firewalls you must open them, or pin the
> distribution port range (`inet_dist_listen_min`/`inet_dist_listen_max` in
> `rel/vm.args.eex`).

> **Pitfall:** the cookie in `compose.yaml` is fine for a demo and nothing
> else. Anyone with the cookie who can reach the ports can run any code on
> your nodes. Keep it in your platform's secret store.
