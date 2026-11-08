import Config

# The nodes to cluster with, read when each node boots:
# CLUSTER_NODES=kv_a@127.0.0.1,kv_b@127.0.0.1
nodes =
  System.fetch_env!("CLUSTER_NODES")
  |> String.split(",", trim: true)
  |> Enum.map(&String.to_atom/1)

config :kv, cluster_nodes: nodes
