defmodule Library.Application do
  use Application

  @impl true
  def start(_type, _args) do
    Supervisor.start_link([Library.Repo], strategy: :one_for_one, name: Library.Supervisor)
  end
end
