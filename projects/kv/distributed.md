After the OTP chapter, **KV** is a solid single-node service: supervised
buckets, fast reads from ETS, expiring keys. But every key still lives on one
machine. When that machine restarts, crashes or is replaced during a deploy,
the data is gone and nobody can be served.

This chapter spreads the store across several nodes, using only what ships
with Erlang/OTP:

1. **Replicate writes.** Every node runs a replica; replicas find each other
   through a `:pg` group; a write goes to all of them and reads are served
   locally. Lose a node and the others still have the data.

Coming next in this chapter, once the first part has had feedback:
bringing a new node up to date, Mnesia's replicated tables, network
partitions, and forming clusters automatically with `libcluster`.

## Running these examples

Distributed examples need several connected nodes, which browsers can't
provide (they can't open the network sockets nodes use), so they have no Run
button. Every page still shows the real output from running it on multiple
nodes when the site was built.

To run one yourself, download it and start it with a node name, as shown at
the top of each page, for example:

```sh
elixir --name kv08@127.0.0.1 08-replicated-buckets.exs
```

The script starts the other nodes it needs with OTP's `:peer` module, so one
command is enough.
