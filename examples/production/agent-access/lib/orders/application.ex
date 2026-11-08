defmodule Orders.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [Orders.Worker, Orders.AgentAccess]
    Supervisor.start_link(children, strategy: :one_for_one, name: Orders.Supervisor)
  end
end
