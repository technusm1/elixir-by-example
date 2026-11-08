defmodule Quota.ApplicationTest do
  # Uses the meter the application started under the name Quota.Meter, which
  # every test can reach: not async.
  use ExUnit.Case, async: false

  setup do
    send(Quota.Meter, :reset)
    :ok
  end

  test "the application starts a named meter" do
    assert [{Quota.Meter, pid, :worker, [Quota.Meter]}] =
             Supervisor.which_children(Quota.Supervisor)

    assert Process.whereis(Quota.Meter) == pid
    assert Quota.Meter.hit(Quota.Meter, "a") == 1
  end

  test "a second meter can't take the name" do
    spec = {Quota.Meter, name: Quota.Meter, limit: 1, interval: :timer.hours(1)}
    assert {:error, {:already_started, pid}} = start_supervised(spec)
    assert pid == Process.whereis(Quota.Meter)
  end
end
