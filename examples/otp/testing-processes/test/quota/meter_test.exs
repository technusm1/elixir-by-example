defmodule Quota.MeterTest do
  use ExUnit.Case, async: true
  alias Quota.Meter

  # Each test gets its own meter, with a reset an hour away: it never fires
  # during a test unless the test sends `:reset` itself.
  setup do
    meter = start_supervised!({Meter, limit: 2, interval: :timer.hours(1), notify: self()})
    %{meter: meter}
  end

  test "counts hits per key", %{meter: meter} do
    assert Meter.hit(meter, "a") == 1
    assert Meter.hit(meter, "a") == 2
    assert Meter.count(meter, "b") == 0
  end

  test "tells the subscriber once a key is over the limit", %{meter: meter} do
    Meter.hit(meter, "a")
    Meter.hit(meter, "a")
    refute_received {:over_limit, _}

    Meter.hit(meter, "a")
    assert_received {:over_limit, "a"}

    Meter.hit(meter, "a")
    refute_received {:over_limit, _}
  end

  test "forgets every count on reset", %{meter: meter} do
    Meter.hit(meter, "a")
    send(meter, :reset)
    assert Meter.count(meter, "a") == 0
  end

  @tag :capture_log
  test "a bad call crashes the meter and its caller", %{meter: meter} do
    ref = Process.monitor(meter)
    assert {{:function_clause, _stack}, _call} = catch_exit(GenServer.call(meter, :oops))
    assert_receive {:DOWN, ^ref, :process, ^meter, {:function_clause, _stack}}
  end
end
