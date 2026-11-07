defmodule KV.Application do
  use Application

  @impl true
  def start(_type, _args) do
    hosts = Application.fetch_env!(:kv, :cluster_nodes)
    topologies = [kv: [strategy: Cluster.Strategy.Epmd, config: [hosts: hosts, timeout: 500]]]

    children = [
      %{id: :pg, start: {:pg, :start_link, []}},
      {Cluster.Supervisor, [topologies, [name: KV.ClusterSupervisor]]},
      KV.Replica
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: KV.Supervisor)
  end
end
