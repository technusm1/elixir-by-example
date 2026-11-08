defmodule Bank.Application do
  use Application

  @impl true
  def start(_type, _args) do
    Supervisor.start_link([Bank.Repo], strategy: :one_for_one, name: Bank.Supervisor)
  end
end
