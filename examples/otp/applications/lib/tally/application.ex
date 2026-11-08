defmodule Tally.Application do
  use Application

  @impl true
  def start(_type, _args) do
    max = Application.fetch_env!(:tally, :max_counters)

    children = [
      {Registry, keys: :unique, name: Tally.Names},
      {DynamicSupervisor, name: Tally.Counters, max_children: max},
      Tally.Total
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Tally.Supervisor)
  end
end
