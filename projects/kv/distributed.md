After the OTP chapter, **KV** is a solid single-node service: supervised
buckets, fast reads from ETS, expiring keys. But every key still lives on one
machine. When that machine restarts, crashes or is replaced during a deploy,
the data is gone and nobody can be served.

This chapter spreads the store across several nodes, using only what ships
with Erlang/OTP:

1. **Replicate writes.** Every node runs a replica; replicas find each other
   through a `:pg` group; a write goes to all of them and reads are served
   locally. Lose a node and the others still have the data.
2. **Catch up new nodes.** A node that joins copies a snapshot from an
   existing replica, joining the group first so no new write passes it by.
   A small gap remains, and it shows why this is hard to do by hand.
3. **Use Mnesia.** Erlang's built-in database keeps a table on several
   nodes, writes to every copy in a transaction, and copies the table to a
   new node safely.

4. **Form the cluster with libcluster.** Nodes find and connect to each
   other on their own, and reconnect after a dropped connection. libcluster
   is a Hex package, so this step installs it with `Mix.install/1`.

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
command is enough. Step 11 stays outside the cluster it builds, so it needs
no node name: `elixir 11-libcluster.exs`.
