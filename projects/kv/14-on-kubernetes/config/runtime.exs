import Config

# Every pod finds the others by asking DNS for the addresses behind the
# headless Service. Each answer is a pod IP, and the node there is called
# kv@<pod IP> (see RELEASE_NODE in k8s/deployment.yaml).
config :kv,
  topologies: [
    kv: [
      strategy: Cluster.Strategy.Kubernetes.DNS,
      config: [
        service: System.fetch_env!("CLUSTER_SERVICE"),
        application_name: "kv",
        polling_interval: 5_000
      ]
    ]
  ]
