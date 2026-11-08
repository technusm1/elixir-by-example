On Compose (step 13) we named every node ourselves: `kv@kv-a`, `kv@kv-b`, and a
fixed `CLUSTER_NODES` list. On Kubernetes that list doesn't exist. Pods come
and go, get a new IP each time they start, and you scale them up and down
with one number. So every node must discover the others at runtime, and each
node must be named in a way the others can derive from what they discover.

The usual answer, and the one this step uses:

1. A **headless Service** (`clusterIP: None`): a DNS name whose lookup returns
   the IP of every KV pod.
2. Each pod names its node `kv@<its pod IP>`, from an environment variable
   Kubernetes fills in.
3. libcluster's `Kubernetes.DNS` strategy polls that DNS name and connects to
   `kv@<ip>` for every IP it gets back.
4. The cookie comes from a Kubernetes Secret, not from the image or the
   manifest.

## The project

The application now takes its whole libcluster topology from configuration, so
the strategy can differ between environments without code changes.

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

The image is built exactly as in step 13.

```file Dockerfile
```

```file .dockerignore
```

## The Kubernetes objects

```file k8s/service.yaml
```

Kubernetes expands `$(POD_IP)` in `RELEASE_NODE` from the variable defined
before it, so each pod gets a unique node name that matches what libcluster
will build from DNS.

```file k8s/deployment.yaml
```

## Deploy

Build the image and make it available to your cluster: push it to a registry
the cluster pulls from, or load it into a local cluster (`kind load
docker-image kv:0.1.0` for kind). Then create the cookie as a Secret and apply
the manifests.

```sh
docker build -t kv:0.1.0 .
kubectl create secret generic kv-cookie --from-literal=cookie="$(openssl rand -base64 32)"
kubectl apply -f k8s/
kubectl rollout status deployment/kv
```

Every pod should see the other two. `kubectl exec` runs the release script in a
pod, with that pod's environment, so `rpc` reaches the node running there.

```sh
PODS=$(kubectl get pods -l app=kv -o jsonpath='{.items[*].metadata.name}')
set -- $PODS
kubectl exec "$1" -- bin/kv rpc 'IO.inspect(length(Node.list()), label: "connected to")'
kubectl exec "$1" -- bin/kv rpc 'KV.Replica.put("lang", "elixir")'
kubectl exec "$2" -- bin/kv rpc 'IO.inspect(KV.Replica.get("lang"))'
```

Scale up, and the new pod joins by itself within a polling interval:

```sh
kubectl scale deployment/kv --replicas=4
```

> **Pitfall:** a new pod starts with an empty store, and a rolling update
> replaces *every* pod. With this KV (in-memory replicas, as in step 8) a
> rollout can lose all data. Data that must survive belongs in a database, or
> in Mnesia with `disc_copies` on a StatefulSet with persistent volumes.

> **Pitfall:** pod IPs change on every restart, so node names change too.
> Anything that remembers node names (Mnesia's schema, for one) needs stable
> names: run a StatefulSet with a headless Service and use the
> `Kubernetes.DNSSRV` strategy, which names nodes after the pods' stable DNS
> names instead of their IPs.

> **Pitfall:** `publishNotReadyAddresses: true` lets nodes find each other
> before they pass their readiness probe. Without it, a pod that waits for the
> cluster before becoming ready, and a cluster that waits for ready pods, wait
> for each other forever.

> **Pitfall:** Erlang distribution gives anyone holding the cookie full
> control of every node. Keep the cookie in a Secret, and use a
> NetworkPolicy so only KV pods can reach ports 4369 and the distribution
> port.
