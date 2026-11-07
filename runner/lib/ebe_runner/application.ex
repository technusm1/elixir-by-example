defmodule EbeRunner.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    Supervisor.start_link([EbeRunner], strategy: :one_for_one, name: EbeRunner.Supervisor)
  end
end
