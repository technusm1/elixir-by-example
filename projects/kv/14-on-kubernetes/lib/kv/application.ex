defmodule KV.Application do
  use Application

  @impl true
  def start(_type, _args) do
    topologies = Application.fetch_env!(:kv, :topologies)

    children = [
      %{id: :pg, start: {:pg, :start_link, []}},
      {Cluster.Supervisor, [topologies, [name: KV.ClusterSupervisor]]},
      KV.Replica
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: KV.Supervisor)
  end
end
