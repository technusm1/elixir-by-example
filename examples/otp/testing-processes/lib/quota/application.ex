defmodule Quota.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Quota.Meter, name: Quota.Meter, limit: 100, interval: :timer.minutes(1)}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Quota.Supervisor)
  end
end
