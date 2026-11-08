defmodule Shop.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [Shop.Repo, Shop.Relay]
    Supervisor.start_link(children, strategy: :one_for_one, name: Shop.Supervisor)
  end
end
