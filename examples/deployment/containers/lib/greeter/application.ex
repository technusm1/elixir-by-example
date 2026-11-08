defmodule Greeter.Application do
  use Application

  @impl true
  def start(_type, _args) do
    Supervisor.start_link([Greeter.Counter], strategy: :one_for_one, name: Greeter.Supervisor)
  end
end
